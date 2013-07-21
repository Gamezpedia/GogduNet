package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.NetStatusEvent;
	import flash.events.TimerEvent;
	import flash.net.GroupSpecifier;
	import flash.net.NetConnection;
	import flash.net.NetGroup;
	import flash.net.NetStream;
	import flash.utils.Timer;
	import flash.utils.getTimer;
	
	import gogduNet.connection.P2PPeer;
	import gogduNet.events.DataEvent;
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.DataType;
	import gogduNet.utils.ObjectPool;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.SocketSecurity;
	import gogduNet.utils.makePacket;
	import gogduNet.utils.parsePacket;
	
	/** 연결에 성공한 경우 발생한다. 하지만 연결 직후엔 연결이 불안정하여 전송이 (매우)잘 되지 않으므로
	 * 연결이 안정된 후에 통신하는 것이 좋다.
	 * (타이머로 연결 후 일정 시간 뒤에 전송하거나, 연결 시험용 패킷을 연결한 후로 계속 반복해서 보내어
	 * 연결이 안정되었는지를 검사하세요)
	 * </br>(data:"NetGroup.Connect.Success")
	 */
	[Event(name="connect", type="gogduNet.events.GogduNetEvent")]
	/** 비자발적으로 연결이 끊긴 경우 발생(close() 함수로는 발생하지 않는다.)
	 * </br>( data:연결이 끊긴 이유("NetConnection.Connect.AppShutdown" or "NetConnection.Connect.InvalidApp" or
	 * "NetConnection.Connect.Rejected" or "NetConnection.Connect.IdleTimeout") )
	 */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	/** 이웃(다른 피어)과 연결된 경우 발생
	 * </br>(data:연결된 피어의 id)
	 */
	[Event(name="socketConnect", type="gogduNet.events.GogduNetEvent")]
	/** 비자발적으로 이웃(다른 피어)과의 연결이 끊긴 경우 발생
	 * </br>(data:연결된 피어의 peerID)
	 */
	[Event(name="socketClose", type="gogduNet.events.GogduNetEvent")]
	/** 허용되지 않은 대상이 연결을 시도하면 발생
	 * </br>(data:대상의 peerID)
	 */
	[Event(name="unpermittedConnection", type="gogduNet.events.GogduNetEvent")]
	/** 연결에 실패한 경우 발생
	 * </br>( data:연결에 실패한 이유("NetConnection.Connect.Failed" or "NetGroup.Connect.Failed") )
	 */
	[Event(name="connectFail", type="gogduNet.events.GogduNetEvent")]
	/** 정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.
	 * </br>(id:데이터를 보낸 피어의 id, dataType, dataDefinition, data)
	 */
	[Event(name="receiveData", type="gogduNet.events.DataEvent")]
	/** 정상적이지 않은 데이터를 수신했을 때 발생
	 * </br>(id:데이터를 보낸 피어의 id, dataType:DataType.INVALID, dataDefinition:"Wrong" or "Surplus", data:잘못된 패킷 문자열)
	 */
	[Event(name="invalidPacket", type="gogduNet.events.DataEvent")]
	
	/** JSON 문자열을 기반으로 하여 통신하는 어도비 Cirrus P2P 클라이언트
	 * (네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)
	 * 
	 * @langversion 3.0
	 * @playerversion Flash Player 11
	 * @playerversion AIR 3.0
	 */
	public class P2PClient extends ClientBase
	{
		/** 연결 검사용 타이머 */
		private var _timer:Timer;
		
		/** 최대 연결 지연 한계 **/
		private var _connectionDelayLimit:Number;
		
		private var _url:String;
		private var _netGroupName:String;
		private var _groupSpecifier:GroupSpecifier;
		private var _netConnection:NetConnection;
		private var _netGroup:NetGroup;
		private var _netStream:NetStream;
		
		/** 현재 연결되어 있는가를 나타내는 bool 값 */
		private var _isConnected:Boolean;
		/** 연결된 지점의 시간을 나타내는 변수 */
		private var _connectedTime:Number;
		/** 마지막으로 통신한 시각(정확히는 마지막으로 정보를 전송 받은 시각) */
		private var _lastReceivedTime:Number;
		/** 디버그용 기록 */
		private var _record:RecordConsole;
		
		/** peer들을 저장해 두는 배열 */
		private var _peerArray:Vector.<P2PPeer>;
		/** peer의 peer id를 주소값으로 사용하여 저장하는 객체 */
		private var _peerIDTable:Object;
		/** peer 객체의 id(not peerID)를 주소값으로 사용하여 저장하는 객체 */
		private var _idTable:Object;
		
		/** GogduNetEvent.CONNECTION_UPDATE 이벤트 객체 */
		private var _event:GogduNetEvent;
		
		/** 피어 객체용 오브젝트 풀 */
		private var _peerPool:ObjectPool;
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체 */
		private var _socketSecurity:SocketSecurity;
		
		/** <p>url : 접속할 주소(rtmfp)</p>
		 * <p>name : NetGroup 이름</p>
		 * <p>socketSecurity : 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체. 값이 null인 경우 자동으로 생성(new SocketSecurity(false))</p>
		 * <p>timerInterval : 타이머 간격(ms)(GogduNetP2PClient의 timer는 정보 수신을 겸하지 않고 오로지 연결 검사용으로만 쓰이기 때문에 반복 속도(timerInterval)가 조금
		 * 느려도 괜찮습니다.)</p>
		 * <p>connectionDelayLimit : 연결 지연 한계(ms)(여기서 설정한 시간 동안 특정 피어로부터 데이터가 오지 않으면 그 피어와 연결이 끊긴 것으로 간주한다.)</p>
		 */
		public function P2PClient(url:String, netGroupName:String="GogduNet", socketSecurity:SocketSecurity=null, timerInterval:Number=1000, connectionDelayLimit:Number=10000)
		{
			_connectionDelayLimit = connectionDelayLimit;
			_timer = new Timer(timerInterval);
			_url = url;
			_netGroupName = netGroupName;
			
			_groupSpecifier = new GroupSpecifier(_netGroupName);
			_groupSpecifier.multicastEnabled = true;
			_groupSpecifier.objectReplicationEnabled = true;
			_groupSpecifier.routingEnabled = true; 
			_groupSpecifier.postingEnabled = true;
			_groupSpecifier.serverChannelEnabled = true;
			_groupSpecifier.ipMulticastMemberUpdatesEnabled = true;
			
			_netConnection = new NetConnection();
			
			_isConnected = false;
			_connectedTime = -1;
			
			_record = new RecordConsole();
			_peerArray = new Vector.<P2PPeer>();
			_peerIDTable = new Object();
			_idTable = new Object();
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
			
			_peerPool = new ObjectPool(P2PPeer);
			
			if(socketSecurity == null)
			{
				socketSecurity = new SocketSecurity(false);
			}
			_socketSecurity = socketSecurity;
		}
		
		/** 연결할 url 값을 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
		public function get url():String
		{
			return _url;
		}
		public function set url(value:String):void
		{
			if(_isConnected == true)
			{
				return;
			}
			
			_url = value;
		}
		
		/** 연결할 넷 그룹의 이름을 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
		public function get netGroupName():String
		{
			return _netGroupName;
		}
		public function set netGroupName(value:String):void
		{
			if(_isConnected == true)
			{
				return;
			}
			
			_netGroupName = value;
		}
		
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 객체를 가져오거나 설정한다.
		 * (P2PClient에서만 특수하게, SocketSecurity.addSocket() 함수의 address 인자를 peerID로, 
		 * port 인자를 음수로 설정해야 합니다.)
		 */
		public function get socketSecurity():SocketSecurity
		{
			return _socketSecurity;
		}
		public function set socketSecurity(value:SocketSecurity):void
		{
			_socketSecurity = value;
		}
		
		/** 연결 검사용 타이머의 재생 간격을 가져오거나 설정한다.(ms) */
		public function get timerInterval():Number
		{
			return _timer.delay;
		}
		public function set timerInterval(value:Number):void
		{
			_timer.delay = value;
		}
		
		/** 연결 지연 한계를 가져오거나 설정한다. (ms)
		 * 이 시간을 넘도록 정보가 수신되지 않은 경우엔 연결이 끊긴 것으로 간주하고 이쪽에서도 연결을 끊는다.
		 */
		public function get connectionDelayLimit():Number
		{
			return _connectionDelayLimit;
		}
		public function set connectionDelayLimit(value:Number):void
		{
			_connectionDelayLimit = value;
		}
		
		/** 나 자신의 peer id를 가져온다. */
		public function get peerID():String
		{
			/*if(_isConnected == false)
			{
			return;
			}*/
			
			return _netConnection.nearID;
		}
		
		/** 연결되어 있는가를 나타내는 여부를 가져온다. */
		public function get isConnected():Boolean
		{
			return _isConnected;
		}
		
		/** 디버그용 기록을 가진 RecordConsole 객체를 가져온다. */
		public function get record():RecordConsole
		{
			return _record;
		}
		
		/** 피어 객체용 오브젝트 풀을 가져온다. */
		public function get peerPool():ObjectPool
		{
			return _peerPool;
		}
		
		/** 연결된 후 시간이 얼마나 지났는지를 나타내는 값을 가져온다.(ms) */
		public function get elapsedTimeAfterConnected():Number
		{
			if(_isConnected == false)
			{
				return -1;
			}
			
			return getTimer() - _connectedTime;
		}
		
		/** 마지막으로 연결된 시각으로부터 지난 시간을 가져온다.(ms) */
		public function get elapsedTimeAfterLastReceived():Number
		{
			return getTimer() - _lastReceivedTime;
		}
		
		/** 연결되어 있는 peer의 수를 가져온다.(넷 그룹의 '모든' peer가 아니라 '나와 연결된' peer의 수.)
		 * 단순히 연결한 피어의 수이므로, 수에 포함되어 있는 모든 피어와의 연결이 안정되어 있는 것은 아니다. */
		public function get numPeers():uint
		{
			return _peerArray.length;
		}
		
		/** 마지막으로 연결된 시각을 갱신한다.
		 * (정보를 수신한 경우 자동으로 이 함수가 실행되어 갱신된다.)
		 */
		private function updateLastReceivedTime():void
		{
			_lastReceivedTime = getTimer();
			dispatchEvent(_event);
		}
		
		/** P2P 연결을 시도한다. */
		public function connect():void
		{
			if(!_url || _isConnected == true)
			{
				return;
			}
			
			_netConnection.addEventListener(NetStatusEvent.NET_STATUS, _onNetStatus);
			_netConnection.connect(_url);
		}
		
		/** P2P 연결을 끊는다. */
		public function close():void
		{
			if(_isConnected == false)
			{
				return;
			}
			
			var i:int;
			var peer:P2PPeer;
			
			for(i = 0; i < _peerArray.length; i += 1)
			{
				if(!_peerArray[i])
				{
					continue;
				}
				
				peer = _peerArray[i];
				
				peer.removeEventListener(NetStatusEvent.NET_STATUS, _onNetStatus);
				_idTable[peer.id] = null;
				peer.netStream.close();
				peer.dispose();
			}
			
			_peerArray.length = 0;
			_peerIDTable = {};
			_idTable = {};
			_peerPool.clear();
			
			_netStream.close();
			
			_netGroup.close();
			_netGroup.removeEventListener(NetStatusEvent.NET_STATUS, _onNetStatus);
			
			_netConnection.close();
			_netConnection.removeEventListener(NetStatusEvent.NET_STATUS, _onNetStatus);
			_netConnection = new NetConnection(); //NetConnection is non reusable after NetConnection.close()
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			
			_record.addRecord("Connection to close(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")", true);
			_isConnected = false;
		}
		
		public function dispose():void
		{
			close();
			
			_timer = null;
			
			_url = null;
			_netGroupName = null;
			
			_groupSpecifier = null;
			_netConnection = null;
			_netGroup = null;
			
			if(_netStream){_netStream.dispose();}
			_netStream = null;
			
			_record.dispose();
			_record = null;
			
			_peerArray = null;
			_peerIDTable = null;
			_idTable = null;
			
			_event = null;
			
			_peerPool.dispose();
			_peerPool = null;
			
			_socketSecurity.dispose();
			_socketSecurity = null;
			
			_isConnected = false;
		}
		
		/** peer id로 peer를 가져온다. */
		public function getPeerByPeerID(targetPeerID:String):P2PPeer
		{
			if(_peerIDTable[targetPeerID] && _peerIDTable[targetPeerID] is P2PPeer)
			{
				return _peerIDTable[targetPeerID];
			}
			
			return null;
		}
		
		/** 식별용 id로 peer를 가져온다. */
		public function getPeerByID(id:String):P2PPeer
		{
			if(_idTable[id] && _idTable[id] is P2PPeer)
			{
				return _idTable[id];
			}
			
			return null;
		}
		
		/** 모든 peer를 가져온다. 반환되는 배열은 복사된 값이므로 수정하더라도 내부에 있는 원본 배열은 바뀌지 않는다. */
		public function getPeers(resultVector:Vector.<P2PPeer>=null):Vector.<P2PPeer>
		{
			if(resultVector == null)
			{
				resultVector = new Vector.<P2PPeer>();
			}
			
			var i:uint;
			var peer:P2PPeer;
			
			for(i = 0; i < _peerArray.length; i += 1)
			{
				if(_peerArray[i] == null)
				{
					continue;
				}
				peer =_peerArray[i];
				
				resultVector.push(peer);
			}
			
			return resultVector;
		}
		
		/** 해당 peerID의 통신 스트림을 가져온다. */
		public function getPeerStream(targetPeerID:String):NetStream
		{
			var i:int;
			var peerStream:NetStream;
			
			for(i = 0; i < _netStream.peerStreams.length; i += 1)
			{
				if(!_netStream.peerStreams[i])
				{
					continue;
				}
				
				peerStream = _netStream.peerStreams[i];
				
				if(peerStream.farID == targetPeerID)
				{
					return peerStream;
				}
			}
			
			return null;
		}
		
		/** Definition을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendDefinition(definition:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.DEFINITION, definition);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** String을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendString(definition:String, data:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.STRING, definition, data);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** Array을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendArray(definition:String, data:Array):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.ARRAY, definition, data);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** Integer을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendInteger(definition:String, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.INTEGER, definition, data);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** Unsigned Integer을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendUnsignedInteger(definition:String, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.UNSIGNED_INTEGER, definition, data);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** Rationals을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendRationals(definition:String, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.RATIONALS, definition, data);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** Boolean을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendBoolean(definition:String, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.BOOLEAN, definition, data);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** JSON을 연결되어 있는 모든 피어에게 보낸다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSON(definition:String, data:Object):Boolean
		{
			if(_isConnected == false){return false;}
			
			if(data is String)
			{
				try
				{
					data = JSON.parse(String(data));
				}
				catch(e:Error)
				{
					return false;
				}
			}
			
			var str:String = makePacket(DataType.JSON, definition, data);
			if(str == null){return false;}
			
			_netStream.send("sendData", str);
			return true;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 Definition을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendDefinitionByID(id:String, definition:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.DEFINITION, definition);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 String을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendStringByID(id:String, definition:String, data:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.STRING, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 Array을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendArrayByID(id:String, definition:String, data:Array):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.ARRAY, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 Integer을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendIntegerByID(id:String, definition:String, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.INTEGER, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 Unsigned Integer을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendUnsignedIntegerByID(id:String, definition:String, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.UNSIGNED_INTEGER, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 Rationals을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendRationalsByID(id:String, definition:String, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.RATIONALS, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 Boolean을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendBooleanByID(id:String, definition:String, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.BOOLEAN, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 id(≠peerID)와 일치하는 피어에게 JSON을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 id를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSONByID(id:String, definition:String, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			if(data is String)
			{
				try
				{
					data = JSON.parse(String(data));
				}
				catch(e:Error)
				{
					return false;
				}
			}
			
			var str:String = makePacket(DataType.JSON, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 Definition을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendDefinitionByPeerID(targetPeerID:String, definition:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.DEFINITION, definition);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 String을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendStringByPeerID(targetPeerID:String, definition:String, data:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.STRING, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 Array을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendArrayByPeerID(targetPeerID:String, definition:String, data:Array):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.ARRAY, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 Integer을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendIntegerByPeerID(targetPeerID:String, definition:String, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.INTEGER, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 Unsigned Integer을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendUnsignedIntegerByPeerID(targetPeerID:String, definition:String, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.UNSIGNED_INTEGER, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 Rationals을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendRationalsByPeerID(targetPeerID:String, definition:String, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.RATIONALS, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 Boolean을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendBooleanByPeerID(targetPeerID:String, definition:String, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.BOOLEAN, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		/** 특정 peerID(≠id)와 일치하는 피어에게 JSON을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나, 해당 peerID를 가진 피어가 없는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSONByPeerID(targetPeerID:String, definition:String, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			if(data is String)
			{
				try
				{
					data = JSON.parse(String(data));
				}
				catch(e:Error)
				{
					return false;
				}
			}
			
			var str:String = makePacket(DataType.JSON, definition, data);
			if(str == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[targetPeerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", str);
				return true;
			}
			
			return false;
		}
		
		private function _onNetStatus(e:NetStatusEvent):void
		{
			var info:Object = e.info;
			var code:String = info.code;
			var peer:P2PPeer;
			
			// 연결에 실패한 경우
			if(code == "NetConnection.Connect.Failed" || code == "NetGroup.Connect.Failed")
			{
				_record.addRecord("ConnectFailed(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(code:" + code + ")", true);
				_isConnected = true; //close 함수의 if(_isConnected == false){return;} 때문에
				close();
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, code) );
				return;
			}
			// 연결이 끊긴 경우
			else if(code == "NetConnection.Connect.AppShutdown" || code == "NetConnection.Connect.InvalidApp" || 
				code == "NetConnection.Connect.Rejected" || code == "NetConnection.Connect.IdleTimeout")
			{
				_record.addRecord("Disconnected(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(code:" + code + ")", true);
				close();
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.CLOSE, false, false, code) );
				return;
			}
			else if(code == "NetConnection.Connect.Success")
			{
				//NetGroup is non reusable after NetGroup.close()
				_netGroup = new NetGroup(_netConnection, _groupSpecifier.groupspecWithAuthorizations());
				
				_netStream = new NetStream(_netConnection, NetStream.DIRECT_CONNECTIONS);
				_netStream.client = {onPeerConnect:_onPeerConnect};
				_netStream.publish(_netGroupName);
				return;
			}
			// 연결에 성공한 경우
			else if(code == "NetGroup.Connect.Success")
			{
				_connectedTime = getTimer();
				updateLastReceivedTime();
				
				_netGroup.addEventListener(NetStatusEvent.NET_STATUS, _onNetStatus);
				_timer.start();
				_timer.addEventListener(TimerEvent.TIMER, _timerFunc);
				
				_isConnected = true;
				_record.addRecord("Connected(connectedTime:" + _connectedTime + ")", true);
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT, false, false, code) );
				return;
			}
			//NetGroup에 누군가가 접속한 경우
			else if(code == "NetGroup.Neighbor.Connect")
			{
				updateLastReceivedTime();
				
				var bool:Boolean = false;
				
				if(_socketSecurity.isPermission == true)
				{
					if(_socketSecurity.contain(info.peerID, -1) == true)
					{
						bool = true;
					}
				}
				else if(_socketSecurity.isPermission == false)
				{
					if(_socketSecurity.contain(info.peerID, -1) == false)
					{
						bool = true;
					}
				}
				
				if(bool == false)
				{
					_record.addRecord("Sensed unpermitted connection(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(peerID:" + info.peerID + ")", true);
					dispatchEvent( new GogduNetEvent(GogduNetEvent.UNPERMITTED_CONNECTION, false, false, info.peerID) );
					return;
				}
				
				//피어를 배열에 추가하고 추가된 위치(index)를 가져와 그걸로 피어 객체를 찾는다.
				peer = _peerArray[_addPeer(info.peerID)];
				//해당 피어와의 연결을 갱신
				peer.updateLastReceivedTime();
				
				_record.addRecord("Neighbor connected(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(id:" + peer.id + ", peerID:" + info.peerID + ")", true);
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CONNECT, false, false, peer.id) );
			}
			//NetGroup에서 누군가가 나간 경우
			else if(code == "NetGroup.Neighbor.Disconnect")
			{
				peer = getPeerByPeerID(info.peerID);
				
				if(peer)
				{
					dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, info.peerID) );
					closePeer(peer.id);
				}
			}
		}
		
		private function _onPeerConnect(ns:NetStream):void
		{
			updateLastReceivedTime();
			
			var bool:Boolean = false;
			
			if(_socketSecurity.isPermission == true)
			{
				if(_socketSecurity.contain(ns.farID, -1) == true)
				{
					bool = true;
				}
			}
			else if(_socketSecurity.isPermission == false)
			{
				if(_socketSecurity.contain(ns.farID, -1) == false)
				{
					bool = true;
				}
			}
			
			if(bool == false)
			{
				_record.addRecord("Sensed unpermitted connection(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(peerID:" + ns.farID + ")", true);
				dispatchEvent( new GogduNetEvent(GogduNetEvent.UNPERMITTED_CONNECTION, false, false, ns.farID) );
				ns.close();
				return;
			}
			
			var peer:P2PPeer = _peerArray[_addPeer(ns.farID)];
			peer.updateLastReceivedTime();
		}
		
		/** peer를 배열에 저장해 둔다. 그리고 저장된 인덱스를 반환한다. */
		private function _addPeer(targetPeerID:String):uint
		{
			var i:int;
			for(i = 0; i < _peerArray.length; i += 1)
			{
				if(!_peerArray[i])
				{
					continue;
				}
				
				// 이미 배열에 이 peer가 존재하고 있는 경우
				if(_peerArray[i].peerID == targetPeerID)
				{
					return i;
				}
			}
			
			var ns:NetStream = new NetStream(_netConnection, targetPeerID);
			ns.addEventListener(NetStatusEvent.NET_STATUS, _onNetStatus);
			
			var peer:P2PPeer = _peerPool.getInstance() as P2PPeer;
			peer.initialize();
			peer.setNetStream(ns);
			peer._setParent(this);
			peer._searchForPeerStream(); //must after _setParent()
			
			ns.client = {sendData:peer._getData};
			ns.play(_netGroupName);
			
			_idTable[peer.id] = peer;
			_peerIDTable[targetPeerID] = peer;
			return _peerArray.push(peer)-1;
		}
		
		/** id로 피어를 찾아서 그 피어를 배열에서 제거하고 연결을 끊는다. */
		public function closePeer(id:String):void
		{
			var peer:P2PPeer = getPeerByID(id);
			
			if(peer == null)
			{
				return;
			}
			
			_peerArray.splice( _peerArray.indexOf(peer), 1 );
			_idTable[id] = null;
			_peerIDTable[peer.peerID] = null;
			
			peer.netStream.close();
			if(peer.peerStream){peer.peerStream.close();}
			
			peer.dispose();
			
			_peerPool.returnInstance(peer);
		}
		
		/** peerID로 피어를 찾아서 그 피어를 배열에서 제거하고 연결을 끊는다. */
		public function closePeerByPeerID(peerID:String):void
		{
			var peer:P2PPeer = getPeerByPeerID(peerID);
			
			if(peer == null)
			{
				return;
			}
			
			_peerArray.splice( _peerArray.indexOf(peer), 1 );
			_idTable[peerID] = null;
			_peerIDTable[peer.id] = null;
			
			peer.netStream.close();
			if(peer.peerStream){peer.peerStream.close();}
			
			peer.dispose();
			
			_peerPool.returnInstance(peer);
		}
		
		/** 타이머로 반복되는 함수 */
		private function _timerFunc(e:TimerEvent):void
		{
			_checkConnect();
		}
		
		/** 연결 상태를 검사 */
		private function _checkConnect():void
		{
			var peer:P2PPeer;
			
			for each(peer in _peerArray)
			{
				if(peer == null)
				{
					continue;
				}
				
				// 일정 시간 이상 전송이 오지 않을 경우 접속이 끊긴 것으로 간주하여 이쪽에서도 접속을 끊는다.
				if(peer.elapsedTimeAfterLastReceived > _connectionDelayLimit)
				{
					_record.addRecord("Close connection to peer(NoResponding)(id:" + peer.id + ", peerID:" + peer.peerID + ")", true);
					
					dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, peer.peerID) );
					
					closePeer(peer.peerID);
					continue;
				}
			}
		}
		
		/** 데이터를 수신 */
		internal function _getData(id:String, jsonStr:String):void
		{
			updateLastReceivedTime()
			
			var peer:P2PPeer = getPeerByID(id);
			if(peer == null){return;}
			
			var backupStr:String = jsonStr;
			
			// 필요 없는 잉여 패킷(잘못 전달되었거나 악성 패킷)이 있으면 제거한다.
			if(FILTER_REG_EXP.test(jsonStr) == true)
			{
				_record.addRecord("Sensed surplus packets(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(id:" + 
					peer.id + ", peerID:" + peer.peerID + ")(str:" + backupStr + ")", true);
				
				dispatchEvent( new DataEvent(DataEvent.INVALID_PACKET, false, false, id, DataType.INVALID, "Surplus", backupStr) );
				jsonStr.replace(FILTER_REG_EXP, "");
			}
			
			// 필요한 패킷을 추출한다.
			var regArr:Array = jsonStr.match(EXTRACTION_REG_EXP);
			
			// 만약 패킷이 없거나 1개보다 많을 경우
			if(regArr.length == 0 || regArr.length > 1)
			{
				_record.addRecord("Sensed wrong packets(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(id:" + 
					peer.id + ", peerID:" + peer.peerID + ")(str:" + backupStr + ")", true);
				
				dispatchEvent( new DataEvent(DataEvent.INVALID_PACKET, false, false, id, DataType.INVALID, "Wrong", backupStr) );
				return;
			}
			
			// 패킷에 오류가 있는지를 검사합니다.
			var obj:Object = parsePacket(regArr[0]);
			
			// 패킷에 오류가 있으면
			if(obj == null)
			{
				_record.addRecord("Sensed wrong packets(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(id:" + 
					peer.id + ", peerID:" + peer.peerID + ")(str:" + regArr[0] + ")", true);
				dispatchEvent(new DataEvent(DataEvent.INVALID_PACKET, false, false, id, DataType.INVALID, "Wrong", regArr[0]));
				return;
			}
			// 패킷에 오류가 없으면
			else
			{
				if(obj.t == DataType.DEFINITION)
				{
					/*_record.addRecord("Data received(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(id:" + 
						peer.id + ", peerID:" + peer.peerID + ")", true);*/
					dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, id, obj.t, obj.df, null));
				}
				else
				{
					/*_record.addRecord("Data received(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(id:" + 
						peer.id + ", peerID:" + peer.peerID + ")", true);*/
					dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, id, obj.t, obj.df, obj.dt));
				}
			}
		}
	}
}