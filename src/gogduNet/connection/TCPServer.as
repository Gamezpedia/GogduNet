package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.ProgressEvent;
	import flash.events.ServerSocketConnectEvent;
	import flash.net.ServerSocket;
	import flash.net.Socket;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	
	import gogduNet.connection.TCPSocket;
	import gogduNet.events.DataEvent;
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.ObjectPool;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.SocketSecurity;
	import gogduNet.utils.cloneByteArray;
	import gogduNet.utils.spliceByteArray;
	
	/** <p>허용되지 않은 대상이 연결을 시도하면 발생한다.</p>
	 * <p>( data:{address:대상의 address, port:대상의 포트} )</p>
	 */
	[Event(name="unpermittedConnection", type="gogduNet.events.GogduNetEvent")]
	/** 운영체제 등에 의해 비자발적으로 서버가 닫힌 경우 발생 (close() 함수로는 발생하지 않는다.)
	 */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** <p>어떤 소켓이 성공적으로 접속한 경우 발생</p>
	 * <p>(data:소켓의 id)</p>
	 */
	[Event(name="socketConnect", type="gogduNet.events.GogduNetEvent")]
	/** <p>어떤 소켓의 연결 시도가 서버 최대 인원 초과로 인해 실패한 경우에 발생한다.</p>
	 * <p>연결 실패한 소켓은 바로 끊기지 않으며, 실패했음을 알리는 패킷을 전송한 후 잠깐의 시간 뒤에 자동으로 끊는다.</p>
	 * <p>( data:{address:실패한 소켓의 address, port:실패한 소켓의 포트} )</p>
	 */
	[Event(name="socketConnectFail", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	/** <p>어떤 소켓과의 연결이 비자발적으로 끊긴 경우 발생(closeSocket() 함수로는 발생하지 않는다)</p>
	 * <p>( data:{id:끊긴 소켓의 id, address:끊긴 소켓의 address, port:끊긴 소켓의 포트} )</p>
	 */
	[Event(name="socketClose", type="gogduNet.events.GogduNetEvent")]
	/** <p>데이터를 수신하면 발생.</p>
	 * <p>(이벤트의 data 속성은 수신한 데이터의 바이트 배열이며, 패킷 단위로 구분되지 않습니다.)</p>
	 * <p>(id:데이터를 보낸 소켓의 id, dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="dataCome", type="gogduNet.events.DataEvent")]
	/** <p>정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.</p>
	 * <p>(id:데이터를 보낸 소켓의 id, dataType, dataDefinition, data)</p>
	 */
	[Event(name="dataReceive", type="gogduNet.events.DataEvent")]
	/** <p>정상적이지 않은 데이터를 수신했을 때 발생</p>
	 * <p>(id:데이터를 보낸 소켓의 id, dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="invalidData", type="gogduNet.events.DataEvent")]
	
	/** @langversion 3.0
	 * @playerversion AIR 3.0 Desktop
	 * @playerversion AIR 3.8
	 */
	public class TCPServer extends ClientBase
	{
		/** 연결 검사를 하는 주기 */
		private var _checkConnectionDelay:Number;
		
		/** 최대 연결 지연 한계 **/
		private var _connectionDelayLimit:Number;
		
		/** 서버 소켓 */
		private var _socket:ServerSocket;
		/** 서버 address */
		private var _address:String;
		/** 서버 포트 */
		private var _port:int;
		
		/** 서버가 실행 중인지를 나타내는 bool 값 */
		private var _run:Boolean;
		/** 서버가 시작된 지점의 시간을 나타내는 변수 */
		private var _runnedTime:Number;
		/** 마지막으로 통신한 시각(정확히는 마지막으로 정보를 전송 받은 시각) */
		private var _lastReceivedTime:Number;
		/** 최대 인원 */
		private var _maxSockets:int;
		/** 디버그용 기록 */
		private var _record:RecordConsole;
		
		/** 클라이언트 소켓 배열 */
		private var _socketArray:Vector.<TCPSocket>;
		/** 소켓 객체의 id를 주소값으로 사용하여 저장하는 객체 */
		private var _idTable:Object;
		
		/** GogduNetEvent.CONNECTION_UPDATE 이벤트 객체 */
		private var _event:GogduNetEvent;
		
		/** 소켓용 풀 */
		private var _socketPool:ObjectPool;
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체 */
		private var _socketSecurity:SocketSecurity;
		
		/** <p>serverAddress : 서버로 사용할 address</p>
		 * <p>serverPort : 서버로 사용할 포트</p>
		 * <p>maxSockets : 최대 인원 수 제한.<p/>
		 * 음수로 설정한 경우 따로 제한을 두지 않음. </p>
		 * <p>connectionDelayLimit : 연결 지연 한계(ms)<p/>
		 * (여기서 설정한 시간 동안 소켓으로부터 데이터가 오지 않으면 그 소켓과는 연결이 끊긴 것으로 간주한다.)</p>
		 */
		public function TCPServer(serverAddress:String="0.0.0.0", serverPort:int=0, maxSockets:int=10, socketSecurity:SocketSecurity=null,
								  connectionDelayLimit:Number=10000)
		{
			_checkConnectionDelay = connectionDelayLimit / 5;
			_connectionDelayLimit = connectionDelayLimit;
			
			_socket = new ServerSocket();
			
			_address = serverAddress;
			_port = serverPort;
			
			_run = false;
			_runnedTime = -1;
			_lastReceivedTime = -1;
			_maxSockets = maxSockets;
			_record = new RecordConsole();
			_socketArray = new Vector.<TCPSocket>();
			_idTable = {};
			
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
			_socketPool = new ObjectPool(TCPSocket);
			
			if(socketSecurity == null)
			{
				socketSecurity = new SocketSecurity(false);
			}
			_socketSecurity = socketSecurity;
		}
		
		/** <p>연결 지연 한계 시간을 가져오거나 설정한다.(ms)</p>
		 * <p>이 시간을 넘도록 정보가 수신되지 않은 경우엔 연결이 끊긴 것으로 간주하고 이쪽에서도 연결을 끊는다.</p>
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
		
		/** 플래시 네이티브 서버 소켓을 가져온다. */
		public function get socket():ServerSocket
		{
			return _socket;
		}
		
		/** 서버의 address를 가져오거나 설정한다. 설정은 서버가 실행되고 있지 않을 때에만 할 수 있다. */
		public function get address():String
		{
			return _address;
		}
		public function set address(value:String):void
		{
			if(_run == true)
			{
				return;
			}
			
			_address = value;
		}
		
		/** 서버의 포트를 가져오거나 설정한다. 설정은 서버가 실행되고 있지 않을 때에만 할 수 있다. */
		public function get port():int
		{
			return _port;
		}
		public function set port(value:int):void
		{
			if(_run == true)
			{
				return;
			}
			
			_port = value;
		}
		
		/** 서버가 실행 중인지를 나타내는 값을 가져온다. */
		public function get isRunning():Boolean
		{
			return _run;
		}
		
		/** <p>서버의 최대 인원 제한 수를 가져오거나 설정한다.</p>
		 * <p>(이 값은 새로 들어오는 연결에만 영향을 주며, 기존 연결은 끊어지지 않는다.)</p> */
		public function get maxSockets():int
		{
			return _maxSockets;
		}
		public function set maxSockets(value:int):void
		{
			_maxSockets = value;
		}
		
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체를 가져오거나 설정한다. */
		public function get socketSecurity():SocketSecurity
		{
			return _socketSecurity;
		}
		public function set socketSecurity(value:SocketSecurity):void
		{
			_socketSecurity = value;
		}
		
		/** 서버의 현재 인원을 가져온다. */
		public function get numSockets():int
		{
			return _socketArray.length;
		}
		
		/** 디버그용 기록을 가지고 있는 RecordConsole 객체를 가져온다. */
		public function get record():RecordConsole
		{
			return _record;
		}
		
		/** 소켓용 오브젝트 풀을 가져온다. */
		public function get socketPool():ObjectPool
		{
			return _socketPool;
		}
		
		/** 서버가 시작된 후 시간이 얼마나 지났는지를 나타내는 Number 값을 가져온다.(ms)
		 * 서버가 실행 중이 아닌 경우엔 -1을 반환한다.
		 */
		public function get elapsedTimeAfterRun():Number
		{
			if(_run == false)
			{
				return -1;
			}
			
			return getTimer() - _runnedTime;
		}
		
		/** 마지막으로 연결된 시각으로부터 지난 시간을 가져온다.(ms) */
		public function get elapsedTimeAfterLastReceived():Number
		{
			return getTimer() - _lastReceivedTime;
		}
		
		/** 마지막으로 연결된 시각을 갱신한다.
		 * (정보가 들어온 경우 자동으로 이 함수가 실행되어 갱신된다.)
		 */
		private function updateLastReceivedTime():void
		{
			_lastReceivedTime = getTimer();
			dispatchEvent(_event);
		}
		
		/** address가 일치하는 소켓을 가져온다.(같은 address를 가진 소켓이 여러 개 존재할 수도 있다) */
		public function getSocketByAddress(address:String):TCPSocket
		{
			var i:int;
			var socket:TCPSocket;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null)
				{
					continue;
				}
				socket =_socketArray[i];
				if(socket.isConnected == false)
				{
					continue;
				}
				
				if(socket.address == address)
				{
					return socket;
				}
			}
			
			return null;
		}
		
		/** 포트가 일치하는 소켓을 가져온다.(같은 포트를 가진 소켓이 여러 개 존재할 수도 있다) */
		public function getSocketByPort(port:int):TCPSocket
		{
			var i:int;
			var socket:TCPSocket;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null)
				{
					continue;
				}
				socket =_socketArray[i];
				if(socket.isConnected == false)
				{
					continue;
				}
				
				if(socket.port == port)
				{
					return socket;
				}
			}
			
			return null;
		}
		
		/** address와 포트가 모두 일치하는 소켓을 가져온다.(유일하다) */
		public function getSocketByAddressAndPort(address:String, port:int):TCPSocket
		{
			var i:int;
			var socket:TCPSocket;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null)
				{
					continue;
				}
				socket =_socketArray[i];
				if(socket.isConnected == false)
				{
					continue;
				}
				
				if(socket.address == address && socket.port == port)
				{
					return socket;
				}
			}
			
			return null;
		}
		
		/** id로 소켓을 가져온다.(유일하다) */
		public function getSocketByID(id:String):TCPSocket
		{
			if(_idTable[id] && _idTable[id] is TCPSocket)
			{
				return _idTable[id];
			}
			
			return null;
		}
		
		/** 모든 소켓을 가져온다. 반환되는 배열은 복사된 값이므로 수정하더라도 내부에 있는 원본 배열은 바뀌지 않는다. */
		public function getSockets(resultVector:Vector.<TCPSocket>=null):Vector.<TCPSocket>
		{
			if(resultVector == null)
			{
				resultVector = new Vector.<TCPSocket>();
			}
			
			var i:int;
			var socket:TCPSocket;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null)
				{
					continue;
				}
				socket = _socketArray[i];
				if(socket.isConnected == false)
				{
					continue;
				}
				
				resultVector.push(socket);
			}
			
			return resultVector;
		}
		
		/** address가 일치하는 소켓들을 가져온다. */
		public function getSocketsByAddress(address:String, resultVector:Vector.<TCPSocket>=null):Vector.<TCPSocket>
		{
			if(resultVector == null)
			{
				resultVector = new Vector.<TCPSocket>();
			}
			
			var i:int;
			var socket:TCPSocket;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null)
				{
					continue;
				}
				socket =_socketArray[i];
				if(socket.isConnected == false)
				{
					continue;
				}
				
				if(socket.address == address)
				{
					resultVector.push(socket);
				}
			}
			
			return resultVector;
		}
		
		/** 포트가 일치하는 소켓들을 가져온다. */
		public function getSocketsByPort(port:int, resultVector:Vector.<TCPSocket>=null):Vector.<TCPSocket>
		{
			if(resultVector == null)
			{
				resultVector = new Vector.<TCPSocket>();
			}
			
			var i:int;
			var socket:TCPSocket;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null)
				{
					continue;
				}
				socket =_socketArray[i];
				if(socket.isConnected == false)
				{
					continue;
				}
				
				if(socket.port == port)
				{
					resultVector.push(socket);
				}
			}
			
			return resultVector;
		}
		
		public function bind(address:String, port:int):void
		{
			if(_run == true)
			{
				return;
			}
			
			_address = address;
			_port = port;
		}
		
		public function dispose():void
		{
			var socket:TCPSocket;
			
			while(_socketArray.length > 0)
			{
				socket = _socketArray.pop();
				
				if(socket == null)
				{
					continue;
				}
				
				socket.removeEventListener(Event.CLOSE, _socketClosed);
				socket.removeEventListener(ProgressEvent.SOCKET_DATA, _listen);
				continue;
			}
			
			_socket.close();
			_socket.removeEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.removeEventListener(Event.CLOSE, _closedByOS);
			
			_socket = null;
			_address = null;
			
			_record.dispose();
			_record = null;
			
			_socketArray = null;
			_idTable = null;
			_event = null;
			
			_socketPool.dispose();
			_socketPool = null;
			
			_socketSecurity.dispose();
			_socketSecurity = null;
			
			_run = false;
		}
		
		/** 서버 작동 시작 */
		public function run():void
		{
			if(!_address || _run == true)
			{
				return;
			}
			
			_runnedTime = getTimer();
			_socket.bind(_port, _address);
			_socket.listen();
			_socket.addEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.addEventListener(Event.CLOSE, _closedByOS);
			
			//first 100 : amount per once run
			//second 100 : run delay
			setTimeout(_checkConnection, _checkConnectionDelay, 0, 100, 100);
			
			_run = true;
			_record.addRecord(true, "Opened server(runnedTime:" + _runnedTime + ")");
		}
		
		/** 운영체제에 의해 소켓이 닫힘 */
		private function _closedByOS():void
		{
			_record.addRecord(true, "Closed server by OS(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")");
			_close();
			dispatchEvent(new GogduNetEvent(GogduNetEvent.CLOSE));
		}
		
		/** <p>서버 작동 중지</p>
		 * <p>(네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)</p>
		 */
		public function close():void
		{
			if(_run == false)
			{
				return;
			}
			
			_record.addRecord(true, "Closed server(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")");
			
			_close();
		}
		
		private function _close():void
		{
			var socket:TCPSocket;
			
			while(_socketArray.length > 0)
			{
				socket =_socketArray.pop();
				
				if(socket == null)
				{
					continue;
				}
				
				_removeSocket(socket);
			}
			
			_socketArray.length = 0;
			_idTable = {};
			_socketPool.clear();
			
			_socket.close();
			_socket.removeEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.removeEventListener(Event.CLOSE, _close);
			_socket = new ServerSocket(); //ServerSocket is non reusable after ServerSocket.close()
			
			_run = false;
		}
		
		private function _sendDataToNativeSocket(nativeSocket:Socket, type:uint, definition:uint, data:ByteArray):Boolean
		{
			var packet:ByteArray = Packet.create(type, definition, data);
			if(packet == null){return false;}
			
			nativeSocket.writeBytes(packet, 0);
			nativeSocket.flush();
			return true;
		}
		
		private function _sendSystemDataToNativeSocket(nativeSocket:Socket, definition:uint, data:ByteArray=null):Boolean
		{
			if(_run == false){return false;}
			
			return _sendDataToNativeSocket(nativeSocket, DataType.SYSTEM, definition, data);
		}
		
		private function _sendData(id:String, type:uint, definition:uint, data:ByteArray):Boolean
		{
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			var packet:ByteArray = Packet.create(type, definition, data);
			if(packet == null){return false;}
			
			var nativeSocket:Socket = socket.nativeSocket;
			
			nativeSocket.writeBytes(packet, 0);
			nativeSocket.flush();
			return true;
		}
		
		private function _sendSystemData(id:String, definition:uint, data:ByteArray=null):Boolean
		{
			if(_run == false){return false;}
			
			return _sendData(id, DataType.SYSTEM, definition, data);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDefinition(id:String, definition:uint):Boolean
		{
			if(_run == false){return false;}
			
			return _sendData(id, DataType.DEFINITION, definition, null);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBoolean(id:String, definition:uint, data:Boolean):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeBoolean(data);
			
			return _sendData(id, DataType.BOOLEAN, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendByte(id:String, definition:uint, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(id, DataType.BYTE, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedByte(id:String, definition:uint, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(id, DataType.UNSIGNED_BYTE, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendShort(id:String, definition:uint, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(id, DataType.SHORT, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedShort(id:String, definition:uint, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(id, DataType.UNSIGNED_SHORT, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendInt(id:String, definition:uint, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeInt(data);
			
			return _sendData(id, DataType.INT, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedInt(id:String, definition:uint, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeUnsignedInt(data);
			
			return _sendData(id, DataType.UNSIGNED_INT, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendFloat(id:String, definition:uint, data:Number):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeFloat(data);
			
			return _sendData(id, DataType.FLOAT, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDouble(id:String, definition:uint, data:Number):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeDouble(data);
			
			return _sendData(id, DataType.DOUBLE, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBytes(id:String, definition:uint, data:ByteArray):Boolean
		{
			if(_run == false){return false;}
			
			return _sendData(id, DataType.BYTES, definition, data);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendString(id:String, definition:uint, data:String):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(data, EncodingFormat.encoding);
			
			return _sendData(id, DataType.STRING, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendArray(id:String, definition:uint, data:Array):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(id, DataType.ARRAY, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendObject(id:String, definition:uint, data:Object):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(id, DataType.OBJECT, definition, bytes);
		}
		
		private function _sendDataToAll(type:uint, definition:uint, data:ByteArray):Boolean
		{
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(_sendData(socket.id, type, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		public function sendSystemDataToAll(id:String, definition:uint, data:ByteArray=null):Boolean
		{
			if(_run == false){return false;}
			
			return _sendDataToAll(DataType.SYSTEM, definition, data);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDefinitionToAll(definition:uint):Boolean
		{
			if(_run == false){return false;}
			
			return _sendDataToAll(DataType.DEFINITION, definition, null);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBooleanToAll(id:String, definition:uint, data:Boolean):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeBoolean(data);
			
			return _sendDataToAll(DataType.BOOLEAN, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendByteToAll(id:String, definition:uint, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendDataToAll(DataType.BYTE, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedByteToAll(id:String, definition:uint, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendDataToAll(DataType.UNSIGNED_BYTE, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendShortToAll(id:String, definition:uint, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendDataToAll(DataType.SHORT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedShortToAll(id:String, definition:uint, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendDataToAll(DataType.UNSIGNED_SHORT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendIntToAll(id:String, definition:uint, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeInt(data);
			
			return _sendDataToAll(DataType.INT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedIntToAll(id:String, definition:uint, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeUnsignedInt(data);
			
			return _sendDataToAll(DataType.UNSIGNED_INT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendFloatToAll(id:String, definition:uint, data:Number):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeFloat(data);
			
			return _sendDataToAll(DataType.FLOAT, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDoubleToAll(id:String, definition:uint, data:Number):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeDouble(data);
			
			return _sendDataToAll(DataType.DOUBLE, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBytesToAll(id:String, definition:uint, data:ByteArray):Boolean
		{
			if(_run == false){return false;}
			
			return _sendDataToAll(DataType.BYTES, definition, data);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendStringToAll(id:String, definition:uint, data:String):Boolean
		{
			if(_run == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(data, EncodingFormat.encoding);
			
			return _sendDataToAll(DataType.STRING, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendArrayToAll(id:String, definition:uint, data:Array):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendDataToAll(DataType.ARRAY, definition, bytes);
		}
		
		/** <p>연결되어 있는 모든 소켓에게 데이터를 전송한다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendObjectToAll(id:String, definition:uint, data:Object):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendDataToAll(DataType.OBJECT, definition, bytes);
		}
		
		/** <p>id가 일치하는 소켓과의 연결을 끊는다.</p>
		 * <p>(해당 소켓의 클라이언트에게 패킷을 전송하여 알리지 않고 바로 끊는다.)</p>
		 */
		public function closeSocket(id:String):void
		{
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return;}
			
			_removeSocket(socket);
		}
		
		/** 네이티브 소켓과의 연결을 강제로 끊는다. */
		private function _forcedCloseNativeSocket(nativeSocket:Socket):void
		{
			try
			{
				nativeSocket.close();
			}
			catch(e:Error)
			{
				_record.addErrorRecord(true, e, "It occurred from forced closes nativeSocket connection");
			}
		}
		
		/** 클라이언트 접속 */
		private function _socketConnect(e:ServerSocketConnectEvent):void
		{
			var socket:Socket = e.socket;
			var bool:Boolean = false;
			
			if(_socketSecurity.isPermission == true)
			{
				if(_socketSecurity.contain(socket.remoteAddress, socket.remotePort) == true)
				{
					bool = true;
				}
			}
			else if(_socketSecurity.isPermission == false)
			{
				if(_socketSecurity.contain(socket.remoteAddress, socket.remotePort) == false)
				{
					bool = true;
				}
			}
			
			if(bool == false)
			{
				_record.addRecord(true, "Sensed unpermitted connection(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")(address:" + socket.remoteAddress + 
					", port:" + socket.remotePort + ")");
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.UNPERMITTED_CONNECTION, false, false, {address:socket.remoteAddress, port:socket.remotePort}) );
				
				socket.close();
				return;
			}
			
			// 사용자 포화로 접속 실패
			if(numSockets >= _maxSockets && _maxSockets >= 0)
			{
				_record.addRecord(true, "What socket is failed connect(Saturation)(address:" + socket.remoteAddress + ", port:" + socket.remotePort + ")");
				_sendSystemDataToNativeSocket(socket, DataDefinition.CONNECT_FAIL);
				
				setTimeout(_forcedCloseNativeSocket, 100, socket);
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CONNECT_FAIL, false, false, {address:socket.remoteAddress, port:socket.remotePort}) );
				return;
			}
			
			// 접속 성공
			var tcpSocket:TCPSocket = _addSocket(socket);
			
			_sendSystemDataToNativeSocket(socket, DataDefinition.CONNECT_SUCCESS); // socket == socket2.nativeSocket
			
			_record.addRecord(true, "Client connected(id:" + tcpSocket.id + ", address:" + socket.remoteAddress + ", port:" + socket.remotePort + ")");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CONNECT, false, false, tcpSocket.id) );
		}
		
		private function _addSocket(socket:Socket):TCPSocket
		{
			var tcpSocket:TCPSocket = _socketPool.getInstance() as TCPSocket;
			tcpSocket.initialize();
			tcpSocket._setNativeSocket(socket);
			
			_idTable[tcpSocket.id] = tcpSocket;
			tcpSocket.addEventListener(Event.CLOSE, _socketClosed);
			tcpSocket.addEventListener(ProgressEvent.SOCKET_DATA, _listen);
			tcpSocket.updateLastReceivedTime();
			_socketArray.push(tcpSocket);
			
			return tcpSocket;
		}
		
		private function _removeSocket(socket:TCPSocket):void
		{
			socket.removeEventListener(Event.CLOSE, _socketClosed);
			socket.removeEventListener(ProgressEvent.SOCKET_DATA, _listen);
			
			socket.nativeSocket.close();
			socket.dispose();
			
			_idTable[socket.id] = null;
			
			_socketPool.returnInstance(socket);
			
			var idx:int = _socketArray.indexOf(socket);
			
			// _socketArray에 이 소켓이 존재할 경우
			if(idx != -1)
			{
				// _socketArray에서 이 소켓을 제거한다.
				_socketArray.splice(idx, 1);
			}
		}
		
		private function _socketClosed(e:Event):void
		{
			var socket:TCPSocket = e.currentTarget as TCPSocket;
			
			_record.addRecord(true, "Connection to client is disconnected(id:" + socket.id + ", address:" + socket.address + ", port:" + socket.port + ")");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, {id:socket.id, address:socket.address, port:socket.port}) );
			
			_removeSocket(socket);
		}
		
		/** 클라이언트의 접속을 검사.(Async) */
		private function _checkConnection(startIndex:int, amountPerRun:uint, delay:Number):void
		{
			if(_run == false){return;}
			else if(!_socketArray){return;}
			
			var i:int;
			var socket:TCPSocket;
			var id:String;
			
			for(i = startIndex; (i < startIndex + amountPerRun) && (i < _socketArray.length); i += 1)
			{
				if(!_socketArray[i]){continue;}
				
				socket = _socketArray[i];
				
				if(socket.isConnected == false)
				{
					id = socket.id;
					_removeSocket(socket);
					
					continue;
				}
				
				// 일정 시간 이상 전송이 오지 않을 경우 접속이 끊긴 것으로 간주하여 이쪽에서도 접속을 끊는다.
				if(socket.elapsedTimeAfterLastReceived > _connectionDelayLimit)
				{
					id = socket.id;
					
					_record.addRecord(true, "Disconnects connection to client(NoResponding)(id:" + id + ", address:" + socket.address + ", port:" + socket.port + ")");
					
					sendDefinition(id, DataDefinition.DISCONNECT);
					
					dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, {id:id, address:socket.address, port:socket.port}) );
					
					_removeSocket(socket);
					
					continue;
				}
			}
			
			if(i < _socketArray.length-1)
			{
				setTimeout(_checkConnection, delay, i, amountPerRun, delay);
			}
			else
			{
				setTimeout(_checkConnection, _checkConnectionDelay, 0, amountPerRun, delay);
			}
		}
		
		/** 정보 수신 */
		private function _listen(e:ProgressEvent):void
		{
			var packetBytes:ByteArray; //바이트 배열 형태의 패킷.
			var cameBytes:ByteArray; //이번에 새로 들어온 데이터
			
			var socket:TCPSocket = e.currentTarget as TCPSocket;
			var nativeSocket:Socket = socket.nativeSocket;
			
			//읽을 데이터가 없을 경우
			if(nativeSocket.bytesAvailable <= 0)
			{
				return;
			}
			
			var id:String = socket.id;
			
			//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함이다.
			nativeSocket.endian = Endian.LITTLE_ENDIAN;
			
			cameBytes = new ByteArray();
			//_socket의 데이터를 cameBytes에 쓴다.
			nativeSocket.readBytes(cameBytes);
			
			//마지막 통신 시간을 갱신한다.
			updateLastReceivedTime();
			//소켓의 마지막 통신 시간을 갱신한다.
			socket.updateLastReceivedTime();
			dispatchEvent( new DataEvent(DataEvent.DATA_COME, false, false, id, 0, 0, cameBytes) );
			
			//백업해 놓은 바이트 배열을 가지고 온다.
			packetBytes = _getBackupBytes(socket);
			packetBytes.position = 0;
			packetBytes.writeBytes(cameBytes);
			
			var datas:Vector.<Object> = Packet.parse(packetBytes);
			
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
			
			//남은 데이터를 나중에 다시 쓰기 위해 저장해 둔다.
			_backupData(socket, packetBytes);
		}
		
		/** 백업해 놓은 바이트 배열을 반환한다. */
		private function _getBackupBytes(socket:TCPSocket):ByteArray
		{
			return socket._backupBytes;
		}
		
		/** 다 처리하고 난 후에도 남아 있는(패킷이 다 오지 않아 처리가 안 된) 데이터를 소켓의 _backupBytes에 임시로 저장해 둔다. */
		private function _backupData(socket:TCPSocket, bytes:ByteArray):void
		{
			if(bytes.length > 0)
			{
				socket._backupBytes.clear();
				socket._backupBytes.writeBytes(bytes, 0);
			}
		}
	} // class
} // package