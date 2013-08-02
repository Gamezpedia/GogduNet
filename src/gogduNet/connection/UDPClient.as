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
	import gogduNet.utils.ObjectPool;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.SocketSecurity;
	
	/** 운영체제 등에 의해 비자발적으로 수신이 끊긴 경우 발생 (close() 함수로는 발생하지 않는다.) */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	/** <p>허용되지 않은 대상에게서 정보가 전송되면 발생</p>
	 * <p>( data:{address:대상의 address, port:대상의 포트} )</p>
	 */
	[Event(name="unpermittedConnection", type="gogduNet.events.GogduNetEvent")]
	/** <p>데이터를 수신하면 발생.</p>
	 * <p>(이벤트의 data 속성은 수신한 데이터의 바이트 배열이며, 패킷 단위로 구분되지 않습니다.)</p>
	 * <p>(id:데이터를 보낸 연결의 id, dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="dataCome", type="gogduNet.events.DataEvent")]
	/** <p>정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.</p>
	 * <p>(id:데이터를 보낸 연결의 id, dataType, dataDefinition, data)</p>
	 */
	[Event(name="dataReceive", type="gogduNet.events.DataEvent")]
	/** <p>정상적이지 않은 데이터를 수신했을 때 발생</p>
	 * <p>(id:데이터를 보낸 연결의 id, dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="invalidData", type="gogduNet.events.DataEvent")]
	
	/** @langversion 3.0
	 * @playerversion AIR 3.0 Desktop
	 * @playerversion AIR 3.8
	 */
	public class UDPClient extends ClientBase
	{
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
		
		/** <p>address : 바인드할 local address (주로 자신의 address)</p>
		 * <p>port : 바인드할 local 포트 (주로 자신의 포트)</p>
		 * <p>connectionSecurity : 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체.</p>
		 * <p>값이 null인 경우 자동으로 생성(new SocketSecurity(false))</p>
		 */
		public function UDPClient(address:String="0.0.0.0", port:int=0, connectionSecurity:SocketSecurity=null)
		{
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
			
			_receivedTime = -1;
			
			_record = new RecordConsole();
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
			
			_connectionTable = {};
			_idTable = {};
			
			_connectionPool = new ObjectPool(UDPConnection);
		}
		
		/** <p>클래스 내부의 DatagramSocket 객체를 반환한다.</p>
		 * <p>close() 함수 등으로 수신이 중단되면 이 속성은 새로 생성된 객체로 바뀐다.</p>
		 */
		public function get socket():DatagramSocket
		{
			return _socket;
		}
		
		/** 소켓이 바인딩될 local address를 가져오거나 설정한다. 설정은 수신하고 있지 않을 때에만 할 수 있다. */
		public function get address():String
		{
			return _address;
		}
		public function set address(value:String):void
		{
			if(_isReceiving == true){return;}
			if(_address == value){return;}
			
			_address = value;
			_socket.bind(_port, _address);
		}
		
		/** 소켓이 바인딩될 local 포트를 가져오거나 설정한다. 설정은 수신하고 있지 않을 때에만 할 수 있다. */
		public function get port():int
		{
			return _port;
		}
		public function set port(value:int):void
		{
			if(_isReceiving == true){return;}
			if(_port == value){return;}
			
			_port = value;
			_socket.bind(_port, _address);
		}
		
		/** 소켓이 바인딩될 address와 포트를 설정한다. 수신하고 있지 않을 때에만 할 수 있다. */
		public function bind(address:String, port:int):void
		{
			if(_isReceiving == true){return;}
			if(_address == address && _port == port){return;}
			
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
		 * (정보가 들어온 경우 자동으로 이 함수가 실행되어 갱신된다.)
		 */
		public function updateLastReceivedTime():void
		{
			_lastReceivedTime = getTimer();
			dispatchEvent(_event);
		}
		
		/** 이때까지 나에게 정보를 보낸 모든 연결의 수를 가지고 온다. 단, 비허용되어 전송이 차단된 연결은 포함되지 않는다. */
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
		
		/** address와 포트가 모두 일치하는 연결을 가져온다. */
		public function getConnectionByAddressAndPort(address:String, port:int):UDPConnection
		{
			if(_connectionTable[address])
			{
				if(_connectionTable[address][port])
				{
					return _connectionTable[address][port];
				}
			}
			
			return null;
		}
		
		/** 수신을 시작한 후 나에게 데이터를 전송하였고 소켓 서큐리티 객체에 의해 비허용되지 않은 모든 연결을 가지고 옵니다. */
		public function getConnections():Vector.<UDPConnection>
		{
			var conn:UDPConnection;
			var vector:Vector.<UDPConnection> = new <UDPConnection>[];
			
			for each(conn in _idTable)
			{
				vector.push(conn);
			}
			
			return vector;
		}
		
		/** address가 일치하는 연결들을 가져온다. */
		public function getConnectionsByAddress(address:String):Vector.<UDPConnection>
		{
			var conn:UDPConnection;
			var vector:Vector.<UDPConnection> = new <UDPConnection>[];
			
			if(_connectionTable[address])
			{
				for each(conn in _connectionTable[address])
				{
					vector.push(conn);
				}
			}
			
			return vector;
		}
		
		public function dispose():void
		{
			_socket.close();
			_socket.removeEventListener(Event.CLOSE, _closedByOS);
			
			_socket = null;
			
			_connectionSecurity.dispose();
			_connectionSecurity = null;
			
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
			
			if(_socket.localAddress != _address || _socket.localPort != _port || _socket.bound == false)
			{
				_socket.bind(_port, _address);
			}
			
			_socket.receive();
			
			_receivedTime = getTimer();
			updateLastReceivedTime();
			_record.addRecord(true, "Started receiving(receivedTime:" + _receivedTime + ")");
			
			_socket.addEventListener(Event.CLOSE, _closedByOS);
			_socket.addEventListener(DatagramSocketDataEvent.DATA, _getData);
			
			_isReceiving = true;
		}
		
		/** <p>수신을 중단한다.</p>
		 * <p>(네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)</p>
		 */
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
			_socket.bind(_port, _address);
			
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
		
		private function _sendData(address:String, port:int, type:uint, definition:uint, data:ByteArray):Boolean
		{
			var packet:ByteArray = Packet.create(type, definition, data);
			if(packet == null){return false;}
			
			_socket.send(packet, 0, packet.length, address, port);
			return true;
		}
		
		private function _sendSystemData(address:String, port:int, definition:uint, data:ByteArray=null):Boolean
		{
			return _sendData(address, port, DataType.SYSTEM, definition, data);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDefinition(address:String, port:int, definition:uint):Boolean
		{
			return _sendData(address, port, DataType.DEFINITION, definition, null);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBoolean(address:String, port:int, definition:uint, data:Boolean):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeBoolean(data);
			
			return _sendData(address, port, DataType.BOOLEAN, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendByte(address:String, port:int, definition:uint, data:int):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(address, port, DataType.BYTE, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedByte(address:String, port:int, definition:uint, data:uint):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(address, port, DataType.UNSIGNED_BYTE, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendShort(address:String, port:int, definition:uint, data:int):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(address, port, DataType.SHORT, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedShort(address:String, port:int, definition:uint, data:uint):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(address, port, DataType.UNSIGNED_SHORT, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendInt(address:String, port:int, definition:uint, data:int):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeInt(data);
			
			return _sendData(address, port, DataType.INT, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedInt(address:String, port:int, definition:uint, data:uint):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeUnsignedInt(data);
			
			return _sendData(address, port, DataType.UNSIGNED_INT, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendFloat(address:String, port:int, definition:uint, data:Number):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeFloat(data);
			
			return _sendData(address, port, DataType.FLOAT, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDouble(address:String, port:int, definition:uint, data:Number):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeDouble(data);
			
			return _sendData(address, port, DataType.DOUBLE, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBytes(address:String, port:int, definition:uint, data:ByteArray):Boolean
		{
			return _sendData(address, port, DataType.BYTES, definition, data);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendString(address:String, port:int, definition:uint, data:String):Boolean
		{
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(data, EncodingFormat.encoding);
			
			return _sendData(address, port, DataType.STRING, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendArray(address:String, port:int, definition:uint, data:Array):Boolean
		{
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(address, port, DataType.ARRAY, definition, bytes);
		}
		
		/** <p>address의 port로 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendObject(address:String, port:int, definition:uint, data:Object):Boolean
		{
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(address, port, DataType.OBJECT, definition, bytes);
		}
		
		/** 정보 수신 */
		private function _getData(e:DatagramSocketDataEvent):void
		{
			updateLastReceivedTime();
			
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
				_record.addRecord(true, "Sensed unpermitted connection(elapsedTimeAfterReceived:" + elapsedTimeAfterReceived + ")(address:" + e.srcAddress + 
					", port:" + e.srcPort + ")");
				dispatchEvent( new GogduNetEvent(GogduNetEvent.UNPERMITTED_CONNECTION, false, false, {address:e.srcAddress, port:e.srcPort}) );
				return;
			}
			
			var connection:UDPConnection = _addConnection(e.srcAddress, e.srcPort);
			connection.updateLastReceivedTime();
			
			var id:String = connection.id;
			
			var dataBytes:ByteArray = e.data;
			
			//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함.
			dataBytes.endian = Endian.BIG_ENDIAN;
			
			dispatchEvent( new DataEvent(DataEvent.DATA_COME, false, false, id, 0, 0, dataBytes) );
			
			var datas:Vector.<Object> = Packet.parse(dataBytes);
			
			var i:uint;
			var len:uint = datas.length;
			var data:Object;
			var inData:Object;
			for(i = 0; i < len; i += 1)
			{
				data = datas[i];
				inData = data.packet;
				
				if(data.event == ParsedNode.RECEIVE_EVENT)
				{
					dispatchEvent( new DataEvent(DataEvent.DATA_RECEIVE, false, false, id, inData.type, inData.def, inData.data) );
				}
				if(data.event == ParsedNode.INVALID_EVENT)
				{
					dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, id, 0, 0, inData.data) );
				}
			}
		}
		
		private function _addConnection(address:String, port:int):UDPConnection
		{
			//테이블에 정보가 존재하지 않을 경우 새로 생성
			if(!_connectionTable[address])
			{
				_connectionTable[address] = {};
			}
			
			if(!_connectionTable[address][port])
			{
				var connection:UDPConnection = _connectionPool.getInstance() as UDPConnection;
				_connectionTable[address][port] = connection;
				connection.initialize();
				_idTable[connection.id] = connection;
				connection._setAddress(address);
				connection._setPort(port);
			}
			
			connection = _connectionTable[address][port];
			
			return connection;
		}
	} // class
} // package