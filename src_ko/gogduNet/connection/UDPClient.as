package gogduNet.connection
{
	import flash.events.DatagramSocketDataEvent;
	import flash.events.Event;
	import flash.events.TimerEvent;
	import flash.net.DatagramSocket;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.Timer;
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	
	import gogduNet.events.DataEvent;
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.DataType;
	import gogduNet.utils.Encryptor;
	import gogduNet.utils.ObjectPool;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.SocketSecurity;
	import gogduNet.utils.makePacket;
	import gogduNet.utils.parsePacket;
	
	/** 운영체제 등에 의해 비자발적으로 수신이 끊긴 경우 발생<p/>
	 * (close() 함수로는 발생하지 않는다.)
	 */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	/** 허용되지 않은 대상에게서 정보가 전송되면 발생
	 * <p/>( data:{address:대상의 address, port:대상의 포트} )
	 */
	[Event(name="unpermittedConnection", type="gogduNet.events.GogduNetEvent")]
	/** 어떤 연결이 연결 지연 한계를 초과한 시간 동안 정보를 수신해 오지 않아
	 * 그 연결에 관한 저장된 데이터를 지운 경우 발생
	 * <p/>( data:{id:지워진 연결의 id, address:지워진 연결의 address, port:지워진 연결의 포트} )
	 */
	[Event(name="socketClose", type="gogduNet.events.GogduNetEvent")]
	/** 정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.
	 * <p/>(id:데이터를 보낸 연결의 id, dataType, dataDefinition, data)
	 */
	[Event(name="receiveData", type="gogduNet.events.DataEvent")]
	/** 정상적이지 않은 데이터를 수신했을 때 발생
	 * <p/>(id:데이터를 보낸 연결의 id, dataType:DataType.INVALID, dataDefinition:"Wrong" or "Surplus", data:잘못된 패킷의 ByteArray)
	 */
	[Event(name="invalidPacket", type="gogduNet.events.DataEvent")]
	
	/** JSON 문자열을 기반으로 하여 통신하는 UDP 클라이언트<p/>
	 * (네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)
	 * 
	 * @langversion 3.0
	 * @playerversion AIR 3.0 Desktop
	 * @playerversion AIR 3.8
	 */
	public class UDPClient extends ClientBase
	{
		/** 내부적으로 정보 수신과 연결 검사용으로 사용하는 타이머 */
		private var _timer:Timer;
		
		/** 최대 연결 지연 한계 */
		private var _connectionDelayLimit:Number;
		/** 서버와 마지막으로 통신한 시각(정확히는 마지막으로 서버로부터 정보를 전송 받은 시각) */
		private var _lastReceivedTime:Number;
		
		/** 플래시 네이티브 소켓 */
		private var _socket:DatagramSocket;
		
		/** 소켓이 바인딩된 local address */
		private var _address:String;
		/** 소켓이 바인딩된 local 포트 */
		private var _port:int;
		
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체 */
		private var _connectionSecurity:SocketSecurity;
		
		/** 서버 인코딩 유형(기본값="UTF-8") */
		private var _encoding:String;
		
		/** 현재 수신하고 있는가를 나타내는 bool 값 */
		private var _isReceiving:Boolean;
		/** 연결된 지점의 시간을 나타내는 변수 */
		private var _receivedTime:Number;
		/** 디버그용 기록 */
		private var _record:RecordConsole;
		
		/** GogduNetEvent.CONNECTION_UPDATE 이벤트 객체 */
		private var _event:GogduNetEvent;
		
		/** UDPConnection 객체를 저장해 두는 오브젝트 객체.
		 * _connectionTable[address][port]
		 */
		private var _connectionTable:Object;
		/** 연결 객체의 id를 주소값으로 사용하여 저장하는 객체 */
		private var _idTable:Object;
		
		/** UDPConnection 객체용 오브젝트 풀 */
		private var _connectionPool:ObjectPool;
		
		/** <p>address : 바인드할 local address<p/>
		 * (주로 자신의 address)</p>
		 * <p>port : 바인드할 local 포트<p/>
		 * (주로 자신의 포트)</p>
		 * <p>connectionSecurity : 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체.<p/>
		 * 값이 null인 경우 자동으로 생성(new SocketSecurity(false))</p>
		 * <p>timerInterval : 정보 수신과 연결 검사를 할 때 사용할 타이머의 반복 간격(ms)</p>
		 * <p>connectionDelayLimit : 연결 지연 한계(ms)<p/>
		 * (여기서 설정한 시간 동안 서버로부터 데이터가 오지 않으면 서버와 연결이 끊긴 것으로 간주한다)<p/>
		 * (설명에선 편의상 연결이란 단어를 썼지만, 정확한 의미는 조금 다르다. UDP 통신은 상대가 수신 가능한지를 따지지 않고 그냥 데이터를 보내기만 한다. 설명에서 연결이 끊긴 것으로 간주한다는 말은, 그 대상으로부터 받아 저장해 두고 있던 정보를 없애겠다는 뜻이다.)</p>
		 * <p>encoding : 통신을 할 때 사용할 인코딩 형식</p>
		 */
		public function UDPClient(address:String="0.0.0.0", port:int=0, connectionSecurity:SocketSecurity=null, 
								  timerInterval:Number=100, connectionDelayLimit:Number=10000, 
								  encoding:String="UTF-8")
		{
			_timer = new Timer(timerInterval);
			
			_connectionDelayLimit = connectionDelayLimit;
			_lastReceivedTime = -1;
			
			_address = address;
			_port = port;
			
			_socket = new DatagramSocket();
			_socket.bind(_port, _address);
			
			if(connectionSecurity == null)
			{
				connectionSecurity = new SocketSecurity(false);
			}
			_connectionSecurity = connectionSecurity;
			
			_encoding = encoding;
			
			_receivedTime = -1;
			
			_record = new RecordConsole();
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
			
			_connectionTable = {};
			_idTable = {};
			
			_connectionPool = new ObjectPool(UDPConnection);
		}
		
		/** 내부적으로 정보 수신이나 연결 검사 등을 위해 사용되는 타이머의 재생 간격을 가져오거나 설정한다.(ms) */
		public function get timerInterval():Number
		{
			return _timer.delay;
		}
		public function set timerInterval(value:Number):void
		{
			_timer.delay = value;
		}
		
		/** 연결 지연 한계 시간을 가져오거나 설정한다.(ms)
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
		
		/** 플래시 네이티브 소켓을 가져온다. */
		public function get socket():DatagramSocket
		{
			return _socket;
		}
		
		/** 소켓이 바인딩된 local address를 가져오거나 설정한다. 설정은 수신하고 있지 않을 때에만 할 수 있다. */
		public function get address():String
		{
			return _address;
		}
		public function set address(value:String):void
		{
			if(_isReceiving == true)
			{
				return;
			}
			
			_address = value;
			_socket.bind(_port, _address);
		}
		
		/** 소켓이 바인딩된 local 포트를 가져오거나 설정한다. 설정은 수신하고 있지 않을 때에만 할 수 있다. */
		public function get port():int
		{
			return _port;
		}
		public function set port(value:int):void
		{
			if(_isReceiving == true)
			{
				return;
			}
			
			_port = value;
			_socket.bind(_port, _address);
		}
		
		/** 소켓이 바인딩된 address와 포트를 설정한다. 수신하고 있지 않을 때에만 할 수 있다. */
		public function bind(address:String, port:int):void
		{
			if(_isReceiving == true)
			{
				return;
			}
			
			_address = address;
			_port = port;
			_socket.bind(_port, _address);
		}
		
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체를 가져오거나 설정한다. */
		public function get connectionSecurity():SocketSecurity
		{
			return _connectionSecurity;
		}
		public function set connectionSecurity(value:SocketSecurity):void
		{
			_connectionSecurity = value;
		}
		
		/** 통신 인코딩 유형을 가져오거나 설정한다. 설정은 수신하고 있지 않을 때에만 할 수 있다. */
		public function get encoding():String
		{
			return _encoding;
		}
		public function set encoding(value:String):void
		{
			if(_isReceiving == true)
			{
				return;
			}
			
			_encoding = value;
		}
		
		/** 현재 데이터를 수신하고 있는지를 나타내는 값을 가져온다. */
		public function get isReceiving():Boolean
		{
			return _isReceiving;
		}
		
		/** 디버그용 기록을 가지고 있는 RecordConsole 객체를 가져온다. */
		public function get record():RecordConsole
		{
			return _record;
		}
		
		/** UDPConnection용 오브젝트 풀을 가져온다. */
		public function get connectionPool():ObjectPool
		{
			return _connectionPool;
		}
		
		/** 수신을 시작한 후 시간이 얼마나 지났는지를 나타내는 Number 값을 가져온다.(ms) */
		public function get elapsedTimeAfterReceived():Number
		{
			if(_isReceiving == false)
			{
				return -1;
			}
			
			return getTimer() - _receivedTime;
		}
		
		/** 마지막으로 연결된 시각으로부터 지난 시간을 가져온다.(ms) */
		public function get elapsedTimeAfterLastReceived():Number
		{
			return getTimer() - _lastReceivedTime;
		}
		
		/** 마지막으로 연결된 시각을 갱신한다.
		 * (서버에게서 정보가 들어온 경우 자동으로 이 함수가 실행되어 갱신된다.)
		 */
		public function updateLastReceivedTime():void
		{
			_lastReceivedTime = getTimer();
			dispatchEvent(_event);
		}
		
		/** 연결 중인 수를 가지고 온다.<p/>
		 * ( 편의상 연결이란 단어를 썼지만, 정확히는 최근에(connectionDelayLimit를 초과하지 않은 시간 안에)
		 * 통신(데이터를 나에게 전송)한 연결들의 수 )
		 */
		public function get numConnections():uint
		{
			var i:Object;
			var j:Object;
			var num:uint = 0;
			
			for each(i in _connectionTable)
			{
				for each(j in i)
				{
					num += 1;
				}
			}
			
			return num;
		}
		
		/** id가 일치하는 연결을 가져온다. */
		public function getConnectionByID(id:String):UDPConnection
		{
			if(_idTable[id] && _idTable[id] is UDPConnection)
			{
				return _idTable[id];
			}
			
			return null;
		}
		
		public function dispose():void
		{
			_socket.close();
			_socket.removeEventListener(Event.CLOSE, _closedByOS);
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			_timer = null;
			
			_socket = null;
			
			_connectionSecurity.dispose();
			_connectionSecurity = null;
			_encoding = null;
			
			_record.dispose();
			_record = null;
			
			_event = null;
			_connectionTable = null;
			_idTable = null;
			_connectionPool.dispose();
			_connectionPool = null;
			
			_isReceiving = false;
		}
		
		/** 바인딩된 Address 주소 및 포트에서 들어오는 패킷을 수신할 수 있도록 합니다.
		 * (UDPClient 클래스는 별도의 connect() 함수가 없습니다. 특정한 대상의 데이터만 수신하고 싶다면 
		 * socketSecurity 속성을 설정하세요.)
		 */
		public function receive():void
		{
			if(!_address || _isReceiving == true)
			{
				return;
			}
			
			_socket.bind(_port, _address);
			_socket.receive();
			
			_receivedTime = getTimer();
			updateLastReceivedTime();
			_record.addRecord(true, "Started receiving(receivedTime:" + _receivedTime + ")");
			
			_socket.addEventListener(Event.CLOSE, _closedByOS);
			_socket.addEventListener(DatagramSocketDataEvent.DATA, _getData);
			_timer.start();
			_timer.addEventListener(TimerEvent.TIMER, _timerFunc);
			
			_isReceiving = true;
		}
		
		/** 수신을 중단한다. */
		public function close():void
		{
			if(_isReceiving == false)
			{
				return;
			}
			
			_record.addRecord(true, "Stopped receiving(elapsedTimeAfterReceived:" + elapsedTimeAfterReceived + ")");
			_close();
		}
		
		private function _close():void
		{
			_socket.close();
			_socket.removeEventListener(Event.CLOSE, _closedByOS);
			_socket.removeEventListener(DatagramSocketDataEvent.DATA, _getData);
			_socket = new DatagramSocket(); //DatagramSocket is non reusable after DatagramSocket.close()
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			
			_connectionTable = {};
			_idTable = {};
			_connectionPool.clear();
			
			_isReceiving = false;
		}
		
		/** 운영체제에 의해 소켓이 닫힘 */
		private function _closedByOS():void
		{
			_record.addRecord(true, "Stopped receiving by OS(elapsedTimeAfterReceived:" + elapsedTimeAfterReceived + ")");
			_close();
			dispatchEvent(new GogduNetEvent(GogduNetEvent.CLOSE));
		}
		
		/** 특정 address의 특정 포트로 Definition을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendDefinition(address:String, port:int, definition:String):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var str:String = makePacket(DataType.DEFINITION, definition);
			if(str == null){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 특정 address의 특정 포트로 String을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendString(address:String, port:int, definition:String, data:String):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var str:String = makePacket(DataType.STRING, definition, data);
			if(str == null){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 특정 address의 특정 포트로 Array을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendArray(address:String, port:int, definition:String, data:Array):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var str:String = makePacket(DataType.ARRAY, definition, data);
			if(str == null){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 특정 address의 특정 포트로 Integer을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendInteger(address:String, port:int, definition:String, data:int):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var str:String = makePacket(DataType.INTEGER, definition, data);
			if(str == null){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 특정 address의 특정 포트로 Unsigned Integer을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendUnsignedInteger(address:String, port:int, definition:String, data:uint):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var str:String = makePacket(DataType.UNSIGNED_INTEGER, definition, data);
			if(str == null){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 특정 address의 특정 포트로 Rationals을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendRationals(address:String, port:int, definition:String, data:Number):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var str:String = makePacket(DataType.RATIONALS, definition, data);
			if(str == null){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 특정 address의 특정 포트로 Boolean을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendBoolean(address:String, port:int, definition:String, data:Boolean):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var str:String = makePacket(DataType.BOOLEAN, definition, data);
			if(str == null){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 특정 address의 특정 포트로 JSON을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSON(address:String, port:int, definition:String, data:Object):Boolean
		{
			if(_isReceiving == false){return false;}
			
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
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, _encoding);
			_socket.send(bytes, 0, bytes.length, address, port);
			return true;
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 Definition을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendDefinitionByID(id:String, definition:String):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendDefinition(conn.address, conn.port, definition);
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 String을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendStringByID(id:String, definition:String, data:String):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendString(conn.address, conn.port, definition, data);
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 Array을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendArrayByID(id:String, definition:String, data:Array):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendArray(conn.address, conn.port, definition, data);
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 Integer을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendIntegerByID(id:String, definition:String, data:int):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendInteger(conn.address, conn.port, definition, data);
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 Unsigned Integer을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendUnsignedIntegerByID(id:String, definition:String, data:uint):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendUnsignedInteger(conn.address, conn.port, definition, data);
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 Rationals을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendRationalsByID(id:String, definition:String, data:Number):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendRationals(conn.address, conn.port, definition, data);
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 Boolean을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 */
		public function sendBooleanByID(id:String, definition:String, data:Boolean):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendBoolean(conn.address, conn.port, definition, data);
		}
		
		/** 최근(connectionDelayLimit를 초과하지 않음)에 통신하여 저장되어 있는 연결 중에서
		 * id가 일치하는 연결로 JSON을 전송한다.
		 * 패킷 형식에 맞지 않는 등의 이유로 전송이 안 된 경우 false를, 그 외엔 true를 반환한다.
		 * (수신하고 있지 않은 상태(isReceiving==false)에서도 전송할 수 있다)
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSONByID(id:String, definition:String, data:Object):Boolean
		{
			var conn:UDPConnection = getConnectionByID(id);
			if(conn == null){return false;}
			
			return sendJSON(conn.address, conn.port, definition, data);
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendDefinition.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 */
		public function sendDefinitionToAll(definition:String):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendDefinition(conn.address, conn.port, definition) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendString.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 */
		public function sendStringToAll(definition:String, data:String):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendString(conn.address, conn.port, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendArray.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 */
		public function sendArrayToAll(definition:String, data:Array):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendArray(conn.address, conn.port, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendInteger.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 */
		public function sendIntegerToAll(definition:String, data:int):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendInteger(conn.address, conn.port, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendUnsignedInteger.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 */
		public function sendUnsignedIntegerToAll(definition:String, data:uint):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendUnsignedInteger(conn.address, conn.port, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendRationals.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 */
		public function sendRationalsToAll(definition:String, data:Number):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendRationals(conn.address, conn.port, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendBoolean.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 */
		public function sendBooleanToAll(definition:String, data:Boolean):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendBoolean(conn.address, conn.port, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** connectionSecurity에 있는 모든 연결 목록에게 sendJSON.
		 * isPermission 속성이 true일 경우 모든 허용된 연결에게, false일 경우 모든 비허용된 목록에게 전송합니다.
		 * (즉, isPermission 속성의 값과는 상관없이 connectionSecurity에 등록된 모든 연결에게 전송합니다)
		 * 하나의 연결에게라도 전송이 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔 false를, 그 외엔 true를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSONToAll(definition:String, data:Object):Boolean
		{
			if(_isReceiving == false){return false;}
			
			var i:uint;
			var conn:Object;
			var tf:Boolean = true;
			var conns:Vector.<Object> = _connectionSecurity.sockets;
			
			for(i = 0; i < conns.length; i += 1)
			{
				if(!conns[i])
				{
					continue;
				}
				conn = conns[i];
				
				if(sendJSON(conn.address, conn.port, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 정보 수신 */
		private function _getData(e:DatagramSocketDataEvent):void
		{
			updateLastReceivedTime();
			
			var connection:UDPConnection;
			var bool:Boolean = false;
			
			if(_connectionSecurity.isPermission == true)
			{
				if(_connectionSecurity.contain(e.srcAddress, e.srcPort) == true)
				{
					bool = true;
				}
			}
			else if(_connectionSecurity.isPermission == false)
			{
				if(_connectionSecurity.contain(e.srcAddress, e.srcPort) == false)
				{
					bool = true;
				}
			}
			
			if(bool == false)
			{
				connection = _connectionPool.getInstance() as UDPConnection;
				connection.initialize();
				connection._setAddress(e.srcAddress);
				connection._setPort(e.srcPort);
				connection.updateLastReceivedTime();
				
				_record.addRecord(true, "Sensed unpermitted connection(elapsedTimeAfterReceived:" + elapsedTimeAfterReceived + ")(address:" + connection.address + 
					", port:" + connection.port + ")");
				dispatchEvent( new GogduNetEvent(GogduNetEvent.UNPERMITTED_CONNECTION, false, false, {address:e.srcAddress, port:e.srcPort}) );
				return;
			}
			
			//테이블에 정보가 존재하지 않을 경우 새로 생성
			if(!_connectionTable[e.srcAddress])
			{
				_connectionTable[e.srcAddress] = {};
			}
			if(!_connectionTable[e.srcAddress][e.srcPort])
			{
				connection = _connectionPool.getInstance() as UDPConnection;
				_connectionTable[e.srcAddress][e.srcPort] = connection;
				connection.initialize();
				_idTable[connection.id] = connection;
				connection._setAddress(e.srcAddress);
				connection._setPort(e.srcPort);
			}
			
			connection = _connectionTable[e.srcAddress][e.srcPort];
			
			var data:ByteArray = e.data;
			
			//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함.
			data.endian = Endian.LITTLE_ENDIAN;
			data.position = 0;
			
			//수신한 데이터를 connection의 저장소에 쓴다.
			connection._backupBytes.writeBytes(data, 0, data.length);
			//마지막 연결 시각을 갱신
			connection.updateLastReceivedTime();
		}
		
		/** 해당 연결에 관한 저장된 정보를 제거합니다.
		 * (UDP는 지속적인 연결 없이 단순히 일방적인 전송만 있으므로, 연결을 끊는다는 의미는 아닙니다) */
		public function removeConnection(id:String):void
		{
			var connection:UDPConnection = getConnectionByID(id);
			if(socket == null){return;}
			
			if(!_connectionTable[connection.address][connection.port])
			{
				return;
			}
			
			_connectionTable[connection.address][connection.port] = null;
			_idTable[connection.id] = null;
			connection.dispose();
			connectionPool.returnInstance(connection);
			
			//만약 _connectionTable[connection.address]에 아무것도 존재하지 않을 경우 그것을 제거한다.
			var bool:Boolean = false;
			for each(var obj:Object in _connectionTable[connection.address])
			{
				bool = true;
				break;
			}
			if(bool == false)
			{
				_connectionTable[connection.address] = null;
			}
		}
		
		/** 해당 연결과 마지막 통신 후 시간이 얼마나 지났는지를 검사한다.
		 * 시간이 연결 지연 한계(connectionDelayLimit)을 초과한 경우데이터를 없애고 true를, 그렇지 않으면 false를 반환한다. */
		private function _checkConnect(connection:UDPConnection):Boolean
		{
			//일정 시간 이상 전송이 오지 않을 경우, 저장된 관련 정보를 모두 지운다.(전송을 안 하고 있는 것으로 간주)
			if(connection.elapsedTimeAfterLastReceived > _connectionDelayLimit)
			{
				_record.addRecord(true, "Remove no responding connection's data(address:" + connection.address + ", port:" + connection.port + ")");
				removeConnection(connection.id);
				
				dispatchEvent(new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, {id:connection.id, address:connection.address, port:connection.port}));
				return true;
			}
			
			return false;
		}
		
		/** 타이머로 반복되는 함수 */
		private function _timerFunc(e:TimerEvent):void
		{
			_processData();
		}
		
		/** 수신한 정보를 처리 */
		private function _processData():void
		{
			var obj:Object;
			var connection:UDPConnection;
			
			var packetBytes:ByteArray; // 패킷을 읽을 때 쓰는 바이트 배열.
			var regArray:Array; // 정규 표현식으로 찾은 문자열들을 저장해 두는 배열
			var jsonObj:Object // 문자열을 JSON으로 변환할 때 사용하는 객체
			var packetStr:String; // byte을 String으로 변환하여 읽을 때 쓰는 문자열.
			var i:uint;
			
			for each(obj in _connectionTable)
			{
				for each(connection in obj)
				{
					if(connection == null)
					{
						continue;
					}
					
					if(_checkConnect(connection) == true)
					{
						continue;
					}
					
					connection._backupBytes.position = 0;
					if(connection._backupBytes.bytesAvailable <= 0)
					{
						continue;
					}
					
					//packetBytes이 onnection._backupBytes을 참조한다.
					packetBytes = connection._backupBytes;
					
					// 정보(byte)를 String으로 읽는다.
					try
					{
						packetBytes.position = 0;
						packetStr = packetBytes.readMultiByte(packetBytes.length, _encoding);
						packetBytes.length = 0; //packetBytes == connection._backupBytes
					}
					catch(e:Error)
					{
						_record.addErrorRecord(true, e, "It occurred from packet bytes convert to string");
						continue;
					}
					
					// 필요 없는 잉여 패킷(잘못 전달되었거나 악성 패킷)이 있으면 제거한다.
					if(FILTER_REG_EXP.test(packetStr) == true)
					{
						_record.addRecord(true, "Sensed surplus packets(elapsedTimeAfterReceived:" + elapsedTimeAfterReceived + ")(address:" + connection.address + 
							", port:" + connection.port + ")(str:" + packetStr + ")");
						_record.addByteRecord(true, packetBytes);
						dispatchEvent(new DataEvent(DataEvent.INVALID_PACKET, false, false, connection.id, DataType.INVALID, "Surplus", packetBytes));
						packetStr.replace(FILTER_REG_EXP, "");
					}
					
					//_reg:정규표현식 에 매치되는 패킷을 가져온다.
					regArray = packetStr.match(EXTRACTION_REG_EXP);
					//가져온 패킷을 문자열에서 제거한다.
					packetStr = packetStr.replace(EXTRACTION_REG_EXP, "");
					
					for(i = 0; i < regArray.length; i += 1)
					{
						if(!regArray[i])
						{
							continue;
						}
						
						// 패킷에 오류가 있는지를 검사합니다.
						jsonObj = parsePacket(regArray[i]);
						
						// 패킷에 오류가 있으면
						if(jsonObj == null)
						{
							_record.addRecord(true, "Sensed wrong packets(elapsedTimeAfterReceived:" + elapsedTimeAfterReceived + ")(address:" + connection.address + 
								", port:" + connection.port + ")(str:" + regArray[i] + ")");
							dispatchEvent(new DataEvent(DataEvent.INVALID_PACKET, false, false, connection.id, DataType.INVALID, "Wrong", packetBytes));
							continue;
						}
							// 패킷에 오류가 없으면
						else
						{
							if(jsonObj.t == DataType.DEFINITION)
							{
								/*_record.addRecord(true, "Data received(elapsedTimeAfterReceived:" + 
									elapsedTimeAfterReceived + ")(address:" + connection.address + 
									", port:" + connection.port + ")");*/
								
								dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, connection.id, jsonObj.t, jsonObj.df, null));
							}
							else
							{
								/*_record.addRecord(true, "Data received(elapsedTimeAfterReceived:" + 
									elapsedTimeAfterReceived + ")(address:" + connection.address + 
									", port:" + connection.port + ")");*/
								
								dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, connection.id, jsonObj.t, jsonObj.df, jsonObj.dt));
							}
						}
					}
					
					// 다 처리하고 난 후에도 남아 있는(패킷이 다 오지 않아 처리가 안 된) 정보(byte)를 소켓의 backupBytes에 임시로 저장해 둔다.
					if(packetStr.length > 0)
					{
						packetBytes = connection._backupBytes;
						packetBytes.length = 0;
						packetBytes.position = 0;
						packetBytes.writeMultiByte(packetStr, _encoding);
					}
				}
			}
		}
	} // class
} // package