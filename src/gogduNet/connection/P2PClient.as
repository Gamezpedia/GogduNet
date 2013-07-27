package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.NetStatusEvent;
	import flash.events.TimerEvent;
	import flash.net.GroupSpecifier;
	import flash.net.NetConnection;
	import flash.net.NetGroup;
	import flash.net.NetStream;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.Timer;
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	
	import gogduNet.connection.P2PPeer;
	import gogduNet.events.DataEvent;
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.ObjectPool;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.SocketSecurity;
	
	/** <p>연결에 성공한 경우 발생한다.</p>
	 * <p>하지만 연결 직후엔 연결이 불안정하여 전송이 (매우)잘 되지 않으므로
	 * 연결이 안정된 후에 통신하는 것이 좋다.</p>
	 * <p>(타이머로 연결 후 일정 시간 뒤에 전송하거나, 연결 시험용 패킷을 연결한 후로 계속 반복해서 보내어
	 * 연결이 안정되었는지를 검사하세요)</p>
	 * <p>(data:"NetGroup.Connect.Success")</p>
	 */
	[Event(name="connect", type="gogduNet.events.GogduNetEvent")]
	/** <p>비자발적으로 연결이 끊긴 경우 발생 (close() 함수로는 발생하지 않는다.)</p>
	 * <p>( data:연결이 끊긴 이유("NetConnection.Connect.AppShutdown" or "NetConnection.Connect.InvalidApp" or
	 * "NetConnection.Connect.Rejected" or "NetConnection.Connect.IdleTimeout") )</p>
	 */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	/** <p>이웃(다른 피어)과 연결된 경우 발생</p>
	 * <p>(data:연결된 피어의 id)</p>
	 */
	[Event(name="socketConnect", type="gogduNet.events.GogduNetEvent")]
	/** <p>이웃(다른 피어)과의 연결이 끊긴 경우 발생</p>
	 * <p>(data:끊긴 피어의 peerID)</p>
	 */
	[Event(name="socketClose", type="gogduNet.events.GogduNetEvent")]
	/** <p>허용되지 않은 대상이 연결을 시도하면 발생</p>
	 * <p>(data:대상의 peerID)</p>
	 */
	[Event(name="unpermittedConnection", type="gogduNet.events.GogduNetEvent")]
	/** <p>연결에 실패한 경우 발생</p>
	 * <p>( data:연결에 실패한 이유("Timeout" or "NetConnection.Connect.Failed" or "NetGroup.Connect.Failed") )</p>
	 */
	[Event(name="connectFail", type="gogduNet.events.GogduNetEvent")]
	/** <p>정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.</p>
	 * <p>(id:데이터를 보낸 피어의 id, dataType, dataDefinition, data)</p>
	 */
	[Event(name="dataReceive", type="gogduNet.events.DataEvent")]
	/** <p>정상적이지 않은 데이터를 수신했을 때 발생</p>
	 * <p>(id:데이터를 보낸 피어의 id, dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="invalidData", type="gogduNet.events.DataEvent")]
	/** <p>데이터를 수신하면 발생.</p>
	 * <p>(이벤트의 data 속성은 수신한 데이터의 바이트 배열이며, 패킷 단위로 구분되지 않습니다.)</p>
	 * <p>(id:데이터를 보낸 피어의 id, dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="dataCome", type="gogduNet.events.DataEvent")]
	
	/** @langversion 3.0
	 * @playerversion Flash Player 11
	 * @playerversion AIR 3.0
	 */
	public class P2PClient extends ClientBase
	{
		/** 연결 검사를 하는 주기 */
		private var _checkConnectionDelay:Number;
		
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
		 * <p>netGroupName : NetGroup 이름</p>
		 * <p>socketSecurity : 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체.</p>
		 * <p>값이 null인 경우 자동으로 생성(new SocketSecurity(false))</p>
		 * <p>connectionDelayLimit : 연결 지연 한계(ms)</p>
		 * <p>(여기서 설정한 시간 동안 특정 피어로부터 데이터가 오지 않으면 그 피어와 연결이 끊긴 것으로 간주한다.)</p>
		 */
		public function P2PClient(url:String, netGroupName:String="GogduNet", socketSecurity:SocketSecurity=null, connectionDelayLimit:Number=10000)
		{
			_checkConnectionDelay = connectionDelayLimit / 5;
			_connectionDelayLimit = connectionDelayLimit;
			
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
		
		/** <p>통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 객체를 가져오거나 설정한다.</p>
		 * <p>(P2PClient에서만 특수하게, SocketSecurity.addSocket() 함수의 address 인자를 peerID로, 
		 * port 인자를 음수로 설정해야 합니다.)</p>
		 */
		public function get socketSecurity():SocketSecurity
		{
			return _socketSecurity;
		}
		public function set socketSecurity(value:SocketSecurity):void
		{
			_socketSecurity = value;
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
			_checkConnectionDelay = _connectionDelayLimit / 5;
		}
		
		/** 나 자신의 peer id를 가져온다. */
		public function get peerID():String
		{
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
			
			setTimeout(_connectionTimeout, 10000);
		}
		
		private function _connectionTimeout():void
		{
			try
			{
				if(_isConnected == false)
				{
					_close();
					
					_record.addRecord(true, "Failed connection(Timeout)");
					
					dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, "Timeout") );
				}
			}
			catch(e:Error)
			{
			}
		}
		
		/** <p>P2P 연결을 끊는다.</p>
		 * <p>(네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)</p>
		 */
		public function close():void
		{
			if(_isConnected == false)
			{
				return;
			}
			
			_record.addRecord(true, "Connection to close(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");
			
			_close();
		}
		
		private function _close():void
		{
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
			
			_isConnected = false;
		}
		
		public function dispose():void
		{
			_close();
			
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
		
		private function _sendData(type:uint, definition:uint, data:ByteArray):Boolean
		{
			var packet:ByteArray = Packet.create(type, definition, data);
			if(packet == null){return false;}
			
			_netStream.send("sendData", packet);
			return true;
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDefinition(definition:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendData(DataType.DEFINITION, definition, null);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBoolean(definition:uint, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeBoolean(data);
			
			return _sendData(DataType.BOOLEAN, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendByte(definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(DataType.BYTE, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedByte(definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(DataType.UNSIGNED_BYTE, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendShort(definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(DataType.SHORT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedShort(definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(DataType.UNSIGNED_SHORT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendInt(definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeInt(data);
			
			return _sendData(DataType.INT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedInt(definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeUnsignedInt(data);
			
			return _sendData(DataType.UNSIGNED_INT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendFloat(definition:uint, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeFloat(data);
			
			return _sendData(DataType.FLOAT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDouble(definition:uint, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeDouble(data);
			
			return _sendData(DataType.DOUBLE, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBytes(definition:uint, data:ByteArray):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendData(DataType.BYTES, definition, data);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendString(definition:uint, data:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(data, EncodingFormat.encoding);
			
			return _sendData(DataType.STRING, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendArray(definition:uint, data:Array):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(DataType.ARRAY, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendObject(definition:uint, data:Object):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(DataType.OBJECT, definition, bytes);
		}
		
		private function _sendDataByID(id:String, type:uint, definition:uint, data:ByteArray):Boolean
		{
			var packet:ByteArray = Packet.create(type, definition, data);
			if(packet == null){return false;}
			
			var peer:P2PPeer = _idTable[id];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", packet);
				return true;
			}
			
			return false;
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDefinitionByID(id:String, definition:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendDataByID(id, DataType.DEFINITION, definition, null);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBooleanByID(id:String, definition:uint, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeBoolean(data);
			
			return _sendDataByID(id, DataType.BOOLEAN, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendByteByID(id:String, definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendDataByID(id, DataType.BYTE, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedByteByID(id:String, definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendDataByID(id, DataType.UNSIGNED_BYTE, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendShortByID(id:String, definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendDataByID(id, DataType.SHORT, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedShortByID(id:String, definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendDataByID(id, DataType.UNSIGNED_SHORT, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendIntByID(id:String, definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeInt(data);
			
			return _sendDataByID(id, DataType.INT, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedIntByID(id:String, definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeUnsignedInt(data);
			
			return _sendDataByID(id, DataType.UNSIGNED_INT, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendFloatByID(id:String, definition:uint, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeFloat(data);
			
			return _sendDataByID(id, DataType.FLOAT, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDoubleByID(id:String, definition:uint, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeDouble(data);
			
			return _sendDataByID(id, DataType.DOUBLE, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBytesByID(id:String, definition:uint, data:ByteArray):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendDataByID(id, DataType.BYTES, definition, data);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendStringByID(id:String, definition:uint, data:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(data, EncodingFormat.encoding);
			
			return _sendDataByID(id, DataType.STRING, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendArrayByID(id:String, definition:uint, data:Array):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendDataByID(id, DataType.ARRAY, definition, bytes);
		}
		
		/** <p>id가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendObjectByID(id:String, definition:uint, data:Object):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendDataByID(id, DataType.OBJECT, definition, bytes);
		}
		
		private function _sendDataByPeerID(peerID:String, type:uint, definition:uint, data:ByteArray):Boolean
		{
			var packet:ByteArray = Packet.create(type, definition, data);
			if(packet == null){return false;}
			
			var peer:P2PPeer = _peerIDTable[peerID];
			if(peer && peer.peerStream)
			{
				peer.peerStream.send("sendData", packet);
				return true;
			}
			
			return false;
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDefinitionByPeerID(peerID:String, definition:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendDataByPeerID(peerID, DataType.DEFINITION, definition, null);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBooleanByPeerID(peerID:String, definition:uint, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeBoolean(data);
			
			return _sendDataByPeerID(peerID, DataType.BOOLEAN, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendByteByPeerID(peerID:String, definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendDataByPeerID(peerID, DataType.BYTE, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedByteByPeerID(peerID:String, definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendDataByPeerID(peerID, DataType.UNSIGNED_BYTE, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendShortByPeerID(peerID:String, definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendDataByPeerID(peerID, DataType.SHORT, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedShortByPeerID(peerID:String, definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendDataByPeerID(peerID, DataType.UNSIGNED_SHORT, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendIntByPeerID(peerID:String, definition:uint, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeInt(data);
			
			return _sendDataByPeerID(peerID, DataType.INT, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedIntByPeerID(peerID:String, definition:uint, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeUnsignedInt(data);
			
			return _sendDataByPeerID(peerID, DataType.UNSIGNED_INT, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendFloatByPeerID(peerID:String, definition:uint, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeFloat(data);
			
			return _sendDataByPeerID(peerID, DataType.FLOAT, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDoubleByPeerID(peerID:String, definition:uint, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeDouble(data);
			
			return _sendDataByPeerID(peerID, DataType.DOUBLE, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBytesByPeerID(peerID:String, definition:uint, data:ByteArray):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendDataByPeerID(peerID, DataType.BYTES, definition, data);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendStringByPeerID(peerID:String, definition:uint, data:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(data, EncodingFormat.encoding);
			
			return _sendDataByPeerID(peerID, DataType.STRING, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendArrayByPeerID(peerID:String, definition:uint, data:Array):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendDataByPeerID(peerID, DataType.ARRAY, definition, bytes);
		}
		
		/** <p>peerID가 일치하는 특정 피어에게 데이터를 보낸다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendObjectByPeerID(peerID:String, definition:uint, data:Object):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendDataByPeerID(peerID, DataType.OBJECT, definition, bytes);
		}
		
		private function _onNetStatus(e:NetStatusEvent):void
		{
			var info:Object = e.info;
			var code:String = info.code;
			var peer:P2PPeer;
			
			// 연결에 실패한 경우
			if(code == "NetConnection.Connect.Failed" || code == "NetGroup.Connect.Failed")
			{
				_record.addRecord(true, "ConnectFailed(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(code:" + code + ")");
				_close();
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, code) );
				return;
			}
			// 연결이 끊긴 경우
			else if(code == "NetConnection.Connect.AppShutdown" || code == "NetConnection.Connect.InvalidApp" || 
				code == "NetConnection.Connect.Rejected" || code == "NetConnection.Connect.IdleTimeout")
			{
				_record.addRecord(true, "Disconnected(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(code:" + code + ")");
				_close();
				
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
				
				//first 100 : amount per once run
				//second 100 : run delay
				setTimeout(_checkConnection, _checkConnectionDelay, 0, 100, 100);
				
				_isConnected = true;
				_record.addRecord(true, "Connected(connectedTime:" + _connectedTime + ")");
				
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
					_record.addRecord(true, "Sensed unpermitted connection(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(peerID:" + info.peerID + ")");
					dispatchEvent( new GogduNetEvent(GogduNetEvent.UNPERMITTED_CONNECTION, false, false, info.peerID) );
					return;
				}
				
				//피어를 배열에 추가하고 추가된 위치(index)를 가져와 그걸로 피어 객체를 찾는다.
				peer = _peerArray[_addPeer(info.peerID)];
				//해당 피어와의 연결을 갱신
				peer.updateLastReceivedTime();
				
				_record.addRecord(true, "Neighbor connected(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(id:" + peer.id + ", peerID:" + info.peerID + ")");
				
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
				_record.addRecord(true, "Sensed unpermitted connection(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(peerID:" + ns.farID + ")");
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
		
		private function _removePeer(peer:P2PPeer):void
		{
			_peerArray.splice( _peerArray.indexOf(peer), 1 );
			_idTable[peer.id] = null;
			_peerIDTable[peer.peerID] = null;
			
			peer.netStream.close();
			if(peer.peerStream){peer.peerStream.close();}
			
			peer.dispose();
			
			_peerPool.returnInstance(peer);
		}
		
		/** id로 피어를 찾아서 그 피어를 배열에서 제거하고 연결을 끊는다. */
		public function closePeer(id:String):void
		{
			var peer:P2PPeer = getPeerByID(id);
			if(peer == null){return;}
			
			_removePeer(peer);
		}
		
		/** peerID로 피어를 찾아서 그 피어를 배열에서 제거하고 연결을 끊는다. */
		public function closePeerByPeerID(peerID:String):void
		{
			var peer:P2PPeer = getPeerByPeerID(peerID);
			if(peer == null){return;}
			
			_removePeer(peer);
		}
		
		/** 연결 상태를 검사 */
		private function _checkConnection(startIndex:int, amountPerRun:uint, delay:Number):void
		{
			if(_isConnected == false){return;}
			else if(!_peerArray){return;}
			
			var i:int;
			var peer:P2PPeer;
			var id:String;
			
			for(i = startIndex; (i < startIndex + amountPerRun) && (i < _peerArray.length); i += 1)
			{
				if(!_peerArray[i]){continue;}
				
				peer = _peerArray[i];
				
				// 일정 시간 이상 전송이 오지 않을 경우 접속이 끊긴 것으로 간주하여 이쪽에서도 접속을 끊는다.
				if(peer.elapsedTimeAfterLastReceived > _connectionDelayLimit)
				{
					_record.addRecord(true, "Close connection to peer(NoResponding)(id:" + peer.id + ", peerID:" + peer.peerID + ")");
					
					dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, peer.peerID) );
					
					_removePeer(peer);
					continue;
				}
			}
			
			if(i < _peerArray.length-1)
			{
				setTimeout(_checkConnection, delay, i, amountPerRun, delay);
			}
			else
			{
				setTimeout(_checkConnection, _checkConnectionDelay, 0, amountPerRun, delay);
			}
		}
		
		/** 데이터를 수신 */
		internal function _getData(id:String, dataBytes:ByteArray):void
		{
			updateLastReceivedTime();
			
			//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함이다.
			dataBytes.endian = Endian.BIG_ENDIAN;
			
			dispatchEvent( new DataEvent(DataEvent.DATA_COME, false, false, id, 0, 0, dataBytes) );
			
			var peer:P2PPeer = getPeerByID(id);
			if(peer == null){return;}
			
			peer.updateLastReceivedTime();
			
			var datas:Vector.<Object> = Packet.parse(dataBytes);
			
			var i:uint;
			var len:uint = datas.length;
			var data:Object;
			var inData:Object;
			for(i = 0; i < len; i += 1)
			{
				data = datas[i];
				inData = data.packet;
				
				if(data.event == "receive")
				{
					dispatchEvent( new DataEvent(DataEvent.DATA_RECEIVE, false, false, id, inData.type, inData.def, inData.data) );
				}
				if(data.event == "invalid")
				{
					dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, id, 0, 0, inData.data) );
				}
			}
		}
	}
}