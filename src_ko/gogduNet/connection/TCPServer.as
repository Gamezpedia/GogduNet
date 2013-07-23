package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.ServerSocketConnectEvent;
	import flash.events.TimerEvent;
	import flash.net.ServerSocket;
	import flash.net.Socket;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.Timer;
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	
	import gogduNet.utils.DataType;
	import gogduNet.connection.TCPSocket;
	import gogduNet.events.DataEvent;
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.Encryptor;
	import gogduNet.utils.ObjectPool;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.SocketSecurity;
	import gogduNet.utils.makePacket;
	import gogduNet.utils.parsePacket;
	import gogduNet.utils.DataType;
	
	/** 허용되지 않은 대상이 연결을 시도하면 발생한다.
	 * <p/>( data:{address:대상의 address, port:대상의 포트} )
	 */
	[Event(name="unpermittedConnection", type="gogduNet.events.GogduNetEvent")]
	/** 운영체제 등에 의해 비자발적으로 서버가 닫힌 경우 발생<p/>
	 * (close() 함수로는 발생하지 않는다.)
	 */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 어떤 소켓이 성공적으로 접속한 경우 발생
	 * <p/>(data:소켓의 id)
	 */
	[Event(name="socketConnect", type="gogduNet.events.GogduNetEvent")]
	/** 어떤 소켓의 연결 시도가 서버 최대 인원 초과로 인해 실패한 경우에 발생한다.<p/>
	 * 연결 실패한 소켓은 바로 끊기지 않으며, 실패했음을 알리는 패킷을 전송한 후 잠깐의 시간 뒤에 자동으로 끊는다.
	 * <p/>( data:{address:실패한 소켓의 address, port:실패한 소켓의 포트} )
	 */
	[Event(name="socketConnectFail", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	/** 어떤 소켓과의 연결이 비자발적으로 끊긴 경우 발생(closeSocket() 함수로는 발생하지 않는다)
	 * <p/>( data:{id:끊긴 소켓의 id, address:끊긴 소켓의 address, port:끊긴 소켓의 포트} )
	 */
	[Event(name="socketClose", type="gogduNet.events.GogduNetEvent")]
	/** 정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.
	 * <p/>(id:데이터를 보낸 소켓의 id, dataType, dataDefinition, data)
	 */
	[Event(name="receiveData", type="gogduNet.events.DataEvent")]
	/** 정상적이지 않은 데이터를 수신했을 때 발생
	 * <p/>(id:데이터를 보낸 피어의 id, dataType:DataType.INVALID, dataDefinition:"Wrong" or "Surplus", data:잘못된 패킷의 ByteArray)
	 */
	[Event(name="invalidPacket", type="gogduNet.events.DataEvent")]
	
	/** JSON 문자열을 기반으로 하여 통신하는 TCP 서버<p/>
	 * (네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)
	 * 
	 * @langversion 3.0
	 * @playerversion AIR 3.0 Desktop
	 * @playerversion AIR 3.8
	 */
	public class TCPServer extends ClientBase
	{
		/** 내부적으로 정보 수신과 연결 검사용으로 사용하는 타이머 */
		private var _timer:Timer;
		
		/** 최대 연결 지연 한계 **/
		private var _connectionDelayLimit:Number;
		
		/** 서버 소켓 */
		private var _socket:ServerSocket;
		/** 서버 address */
		private var _address:String;
		/** 서버 포트 */
		private var _port:int;
		/** 서버 인코딩 유형(기본값="UTF-8") */
		private var _encoding:String;
		
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
		 * <p>timerInterval : 정보 수신과 연결 검사를 할 때 사용할 타이머의 반복 간격(ms)</p>
		 * <p>connectionDelayLimit : 연결 지연 한계(ms)<p/>
		 * (여기서 설정한 시간 동안 소켓으로부터 데이터가 오지 않으면 그 소켓과는 연결이 끊긴 것으로 간주한다.)</p>
		 * <p>encoding : 통신을 할 때 사용할 인코딩 형식</p>
		 */
		public function TCPServer(serverAddress:String="0.0.0.0", serverPort:int=0, maxSockets:int=10, socketSecurity:SocketSecurity=null, timerInterval:Number=100,
								  connectionDelayLimit:Number=10000, encoding:String="UTF-8")
		{
			_timer = new Timer(timerInterval);
			_connectionDelayLimit = connectionDelayLimit;
			_socket = new ServerSocket();
			
			_address = serverAddress;
			_port = serverPort;
			
			_encoding = encoding;
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
		
		/** 서버의 통신 인코딩 유형을 가져오거나 설정한다. 설정은 서버가 실행되고 있지 않을 때에만 할 수 있다. */
		public function get encoding():String
		{
			return _encoding;
		}
		public function set encoding(value:String):void
		{
			if(_run == true)
			{
				return;
			}
			
			_encoding = value;
		}
		
		/** 서버가 실행 중인지를 나타내는 값을 가져온다. */
		public function get isRunning():Boolean
		{
			return _run;
		}
		
		/** 서버의 최대 인원 제한 수를 가져오거나 설정한다. (이 값은 새로 들어오는 연결에만 영향을 주며, 기존 연결은 끊어지지 않는다.)*/
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
		
		/** address와 포트가 모두 일치하는 소켓들을 가져온다. */
		/*public function getSocketsByAddressAndPort(address:String, port:int, resultVector:Vector.<TCPSocket>=null):Vector.<TCPSocket>
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
				
				if(socket.address == address && socket.port == port)
				{
					resultVector.push(socket);
				}
			}
			
			return resultVector;
		}*/
		
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
				continue;
			}
			
			_socket.close();
			_socket.removeEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.removeEventListener(Event.CLOSE, _closedByOS);
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			_timer = null;
			
			_socket = null;
			_address = null;
			_encoding = null;
			
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
			_timer.start();
			_timer.addEventListener(TimerEvent.TIMER, _timerFunc);
			
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
		
		/** 서버 작동 중지 */
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
				socket.removeEventListener(Event.CLOSE, _socketClosed);
				_idTable[socket.id] = null;
				socket.nativeSocket.close();
				socket.dispose();
			}
			
			_socketArray.length = 0;
			_idTable = {};
			_socketPool.clear();
			
			_socket.close();
			_socket.removeEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.removeEventListener(Event.CLOSE, _close);
			_socket = new ServerSocket(); //ServerSocket is non reusable after ServerSocket.close()
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			
			_run = false;
		}
		
		/** 플래시의 네이티브 소켓으로 Definition를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendDefinitionToNativeSocket(nativeSocket:Socket, definition:String):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = makePacket(DataType.DEFINITION, definition);
			if(str == null){return false;}
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** 플래시의 네이티브 소켓으로 String를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendStringToNativeSocket(nativeSocket:Socket, definition:String, data:String):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = makePacket(DataType.STRING, definition, data);
			if(str == null){return false;}
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** 플래시의 네이티브 소켓으로 Array를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendArrayToNativeSocket(nativeSocket:Socket, definition:String, data:Array):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = makePacket(DataType.ARRAY, definition, data);
			if(str == null){return false;}
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** 플래시의 네이티브 소켓으로 Integer를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendIntegerToNativeSocket(nativeSocket:Socket, definition:String, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = makePacket(DataType.INTEGER, definition, data);
			if(str == null){return false;}
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** 플래시의 네이티브 소켓으로 Unsigned Integer를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendUnsignedIntegerToNativeSocket(nativeSocket:Socket, definition:String, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = makePacket(DataType.UNSIGNED_INTEGER, definition, data);
			if(str == null){return false;}
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** 플래시의 네이티브 소켓으로 Rationals를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendRationalsToNativeSocket(nativeSocket:Socket, definition:String, data:Number):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = makePacket(DataType.RATIONALS, definition, data);
			if(str == null){return false;}
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** 플래시의 네이티브 소켓으로 Boolean를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendBooleanToNativeSocket(nativeSocket:Socket, definition:String, data:Boolean):Boolean
		{
			if(_run == false){return false;}
			
			var str:String = makePacket(DataType.BOOLEAN, definition, data);
			if(str == null){return false;}
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** 플래시의 네이티브 소켓으로 JSON를 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSONToNativeSocket(nativeSocket:Socket, definition:String, data:Object):Boolean
		{
			if(_run == false){return false;}
			
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
			
			nativeSocket.writeMultiByte(str, _encoding);
			nativeSocket.flush();
			return true;
		}
		
		/** id가 일치하는 소켓에게 Definition을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendDefinition(id:String, definition:String):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			return sendDefinitionToNativeSocket(socket.nativeSocket, definition);
		}
		
		/** id가 일치하는 소켓에게 String을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendString(id:String, definition:String, data:String):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			return sendStringToNativeSocket(socket.nativeSocket, definition, data);
		}
		
		/** id가 일치하는 소켓에게 Array을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendArray(id:String, definition:String, data:Array):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			return sendArrayToNativeSocket(socket.nativeSocket, definition, data);
		}
		
		/** id가 일치하는 소켓에게 Integer을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendInteger(id:String, definition:String, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			return sendIntegerToNativeSocket(socket.nativeSocket, definition, data);
		}
		
		/** id가 일치하는 소켓에게 Unsigned Integer을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendUnsignedInteger(id:String, definition:String, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			return sendUnsignedIntegerToNativeSocket(socket.nativeSocket, definition, data);
		}
		
		/** id가 일치하는 소켓에게 Rationals을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendRationals(id:String, definition:String, data:Number):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			return sendRationalsToNativeSocket(socket.nativeSocket, definition, data);
		}
		
		/** id가 일치하는 소켓에게 Boolean을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendBoolean(id:String, definition:String, data:Boolean):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
			return sendBooleanToNativeSocket(socket.nativeSocket, definition, data);
		}
		
		/** id가 일치하는 소켓에게 JSON을 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않거나 id가 일치하는 소켓이 없다는 등의 이유로 전송이
		 * 실패한 경우 true를, 그 외엔 false를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSON(id:String, definition:String, data:Object):Boolean
		{
			if(_run == false){return false;}
			
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return false;}
			
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
			
			return sendJSONToNativeSocket(socket.nativeSocket, definition, data);
		}
		
		/** 연결되어 있는 모든 소켓에게 sendDefinition. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 */
		public function sendDefinitionToAll(definition:String):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendDefinition(socket.id, definition) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 연결되어 있는 모든 소켓에게 sendString. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 */
		public function sendStringToAll(definition:String, data:String):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendString(socket.id, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 연결되어 있는 모든 소켓에게 sendArray. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 */
		public function sendArrayToAll(definition:String, data:Array):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendArray(socket.id, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 연결되어 있는 모든 소켓에게 sendInteger. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 */
		public function sendIntegerToAll(definition:String, data:int):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendInteger(socket.id, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 연결되어 있는 모든 소켓에게 sendUnsignedInteger. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 */
		public function sendUnsignedIntegerToAll(definition:String, data:uint):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendUnsignedInteger(socket.id, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 연결되어 있는 모든 소켓에게 sendRationals. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 */
		public function sendRationalsToAll(definition:String, data:Number):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendRationals(socket.id, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 연결되어 있는 모든 소켓에게 sendBoolean. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 */
		public function sendBooleanToAll(definition:String, data:Boolean):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendBoolean(socket.id, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** 연결되어 있는 모든 소켓에게 sendJSON. 하나의 소켓이라도 전송에 실패(패킷 형식에 맞지 않는 등의 이유로)한 경우엔
		 * false를, 그 외엔 true를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSONToAll(definition:String, data:Object):Boolean
		{
			if(_run == false){return false;}
			
			var i:int;
			var socket:TCPSocket;
			var tf:Boolean = true;
			
			for(i = 0; i < _socketArray.length; i += 1)
			{
				if(_socketArray[i] == null){continue;}
				
				socket = _socketArray[i];
				if(socket.isConnected == false){continue;}
				
				if(sendJSON(socket.id, definition, data) == false)
				{
					tf = false;
				}
			}
			
			return tf;
		}
		
		/** id가 일치하는 소켓과의 연결을 끊는다.
		 * (해당 소켓의 클라이언트에게 패킷을 전송하여 알리지 않고 바로 끊는다.)
		 */
		public function closeSocket(id:String):void
		{
			var socket:TCPSocket = getSocketByID(id);
			if(socket == null){return;}
			
			socket.removeEventListener(Event.CLOSE, _socketClosed);
			_idTable[socket.id] = null;
			
			socket.nativeSocket.close();
			socket.dispose();
			_socketPool.returnInstance(socket);
			_removeSocket(socket);
		}
		
		/** _socketArray에서 socket을 제거한다. 성공적으로 제거한 경우엔 true를,
		 * _socketArray에 socket이 없어서 제거하지 못한 경우엔 false를 반환한다.
		 */
		private function _removeSocket(socket:TCPSocket):void
		{
			var idx:int = _socketArray.indexOf(socket);
			
			// _socketArray에 이 소켓이 존재할 경우
			if(idx != -1)
			{
				// _socketArray에서 이 소켓을 제거한다.
				_socketArray.splice(idx, 1);
			}
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
				sendDefinitionToNativeSocket(socket, "Connect.Fail.Saturation");
				setTimeout(_forcedCloseNativeSocket, 100, socket);
				
				dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CONNECT_FAIL, false, false, {address:socket.remoteAddress, port:socket.remotePort}) );
				return;
			}
			
			// 접속 성공
			var socket2:TCPSocket = _socketPool.getInstance() as TCPSocket;
			socket2.initialize();
			socket2._setNativeSocket(socket);
			
			_idTable[socket2.id] = socket2;
			socket2.addEventListener(Event.CLOSE, _socketClosed);
			socket2.updateLastReceivedTime();
			_socketArray.push(socket2);
			
			sendDefinitionToNativeSocket(socket, "Connect.Success"); // socket == socket2.nativeSocket
			
			_record.addRecord(true, "Client connected(id:" + socket2.id + ", address:" + socket.remoteAddress + ", port:" + socket.remotePort + ")");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CONNECT, false, false, socket2.id) );
		}
		
		private function _socketClosed(e:Event):void
		{
			var socket:TCPSocket = e.currentTarget as TCPSocket;
			socket.removeEventListener(Event.CLOSE, _socketClosed);
			
			_record.addRecord(true, "Connection to client is disconnected(id:" + socket.id + ", address:" + socket.address + ", port:" + socket.port + ")");
			_removeSocket(socket);
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, {id:socket.id, address:socket.address, port:socket.port}) );
			
			_idTable[socket.id] = null;
			socket.nativeSocket.close();
			socket.dispose();
			_socketPool.returnInstance(socket);
		}
		
		/** 타이머로 반복되는 함수 */
		private function _timerFunc(e:TimerEvent):void
		{
			_listen();
		}
		
		/** 클라이언트의 접속을 검사. 문제가 있어 연결을 끊어야 하는 경우 경우 끊고 true, 그렇지 않으면 false를 반환한다. */
		private function _checkConnect(socket:TCPSocket):Boolean
		{
			var id:String = socket.id;
			
			if(socket.isConnected == false)
			{
				socket.removeEventListener(Event.CLOSE, _socketClosed);
				_removeSocket(socket);
				socket.nativeSocket.close();
				socket.dispose();
				
				_idTable[id] = null;
				_socketPool.returnInstance(socket);
				return true;
			}
			
			// 일정 시간 이상 전송이 오지 않을 경우 접속이 끊긴 것으로 간주하여 이쪽에서도 접속을 끊는다.
			if(socket.elapsedTimeAfterLastReceived > _connectionDelayLimit)
			{
				_record.addRecord(true, "Disconnects connection to client(NoResponding)(id:" + id + ", address:" + socket.address + ", port:" + socket.port + ")");
				sendDefinition(id, "GogduNet.Disconnect.NoResponding");
				dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, {id:socket.id, address:socket.address, port:socket.port}) );
				closeSocket(id);
				return true;
			}
			
			return false;
		}
		
		/** 정보 수신 */
		private function _listen():void
		{
			var socket:TCPSocket;
			var socketInSocket:Socket;
			var packetBytes:ByteArray; // 패킷을 읽을 때 쓰는 바이트 배열.
			var bytes:ByteArray; // 패킷을 읽을 때 보조용으로 한 번만 쓰는 일회용 바이트 배열.
			var regArray:Array; // 정규 표현식으로 찾은 문자열들을 저장해 두는 배열
			var jsonObj:Object // 문자열을 JSON으로 변환할 때 사용하는 객체
			var packetStr:String; // byte을 String으로 변환하여 읽을 때 쓰는 문자열.
			var i:int;
			
			for each(socket in _socketArray)
			{
				if(socket == null)
				{
					continue;
				}
				
				if(_checkConnect(socket) == true)
				{
					continue;
				}
				
				socketInSocket = socket.nativeSocket;
				
				if(socketInSocket.bytesAvailable <= 0)
				{
					continue;
				}
				
				// 서버의 마지막 연결 시각을 갱신.
				updateLastReceivedTime();
				// 해당 소켓과의 마지막 연결 시각을 갱신.
				socket.updateLastReceivedTime();
				
				// packetBytes는 socket.packetBytes + socketInSocket의 값을 가지게 된다.
				packetBytes = new ByteArray();
				bytes = socket._backupBytes;
				bytes.position = 0;
				packetBytes.position = 0;
				packetBytes.writeBytes(bytes, 0, bytes.length);
				
				//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함.
				socketInSocket.endian = Endian.LITTLE_ENDIAN;
				socketInSocket.readBytes(packetBytes, packetBytes.length, socketInSocket.bytesAvailable);
				
				bytes.length = 0; //bytes == socket._backupBytes
				
				// 정보(byte)를 String으로 읽는다.
				try
				{
					packetBytes.position = 0;
					packetStr = packetBytes.readMultiByte(packetBytes.length, _encoding);
				}
				catch(e:Error)
				{
					_record.addErrorRecord(true, e, "It occurred from packet bytes convert to string");
					continue;
				}
				
				// 필요 없는 잉여 패킷(잘못 전달되었거나 악성 패킷)이 있으면 제거한다.
				if(FILTER_REG_EXP.test(packetStr) == true)
				{
					_record.addRecord(true, "Sensed surplus packets(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")(id:" + socket.id + ", address:" + socket.address + ", port:" + socket.port + ")(str:" + packetStr + ")");
					_record.addByteRecord(true, packetBytes);
					dispatchEvent(new DataEvent(DataEvent.INVALID_PACKET, false, false, socket.id, DataType.INVALID, "Surplus", packetBytes));
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
						_record.addRecord(true, "Sensed wrong packets(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")(id:" + socket.id + ", address:" + socket.address + ", port:" + socket.port + ")(str:" + regArray[i] + ")");
						dispatchEvent(new DataEvent(DataEvent.INVALID_PACKET, false, false, socket.id, DataType.INVALID, "Wrong", packetBytes));
						continue;
					}
						// 패킷에 오류가 없으면
					else
					{
						if(jsonObj.t == DataType.DEFINITION)
						{
							/*_record.addRecord("Data received(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")(id:" + 
								socket.id + ", address:" + socket.address + ", port:" + socket.port + ")", true);*/
							
							dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, socket.id, jsonObj.t, jsonObj.df, null));
						}
						else
						{
							/*_record.addRecord("Data received(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")(id:" + 
								socket.id + ", address:" + socket.address + ", port:" + socket.port + ")", true);*/
							
							dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, socket.id, jsonObj.t, jsonObj.df, jsonObj.dt));
						}
					}
				}
				
				// 다 처리하고 난 후에도 남아 있는(패킷이 다 오지 않아 처리가 안 된) 정보(byte)를 소켓의 _backupBytes에 임시로 저장해 둔다.
				if(packetStr.length > 0)
				{
					bytes = socket._backupBytes;
					bytes.length = 0;
					bytes.position = 0;
					bytes.writeMultiByte(packetStr, _encoding);
				}
			}
		}
	} // class
} // package