package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.ProgressEvent;
	import flash.events.ServerSocketConnectEvent;
	import flash.net.ServerSocket;
	import flash.net.Socket;
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.SocketSecurity;
	
	/** 허용되지 않은 대상이 연결을 시도하면 발생한다.
	 * <p/>( data:{address:대상의 address, port:대상의 포트} )
	 */
	[Event(name="unpermittedConnection", type="gogduNet.events.GogduNetEvent")]
	/** 운영체제 등에 의해 비자발적으로 연결이 끊긴 경우 발생<p/>
	 * (close() 함수로는 발생하지 않는다.)
	 */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 어떤 소켓이 접속한 경우 발생
	 * <p/>( data:{address:소켓의 address, port:소켓의 포트} )
	 */
	[Event(name="socketConnect", type="gogduNet.events.GogduNetEvent")]
	/** 어떤 소켓과의 연결이 끊긴 경우 발생
	 * <p/>( data:{address:소켓의 address, port:소켓의 포트} )
	 */
	[Event(name="socketClose", type="gogduNet.events.GogduNetEvent")]
	
	/** 정책 파일 전송용 TCP 서버입니다.<p/>
	 * 이 서버에 연결한 소켓에게 정책 파일 문자열을 전송하며,
	 * 일정 시간 뒤에 자동으로 연결을 끊습니다.
	 * 
	 * @langversion 3.0
	 * @playerversion AIR 3.0 Desktop
	 * @playerversion AIR 3.8
	 */
	public class TCPPolicyServer extends ClientBase
	{
		/** 플래시 네이티브 서버 소켓 */
		private var _socket:ServerSocket;
		/** 서버 address */
		private var _address:String;
		/** 서버 포트 */
		private var _port:int;
		
		/** 서버가 실행 중인지를 나타내는 bool 값 */
		private var _run:Boolean;
		/** 서버가 시작된 지점의 시간을 나타내는 변수 */
		private var _runnedTime:Number;
		/** 디버그용 기록 */
		private var _record:RecordConsole;
		
		/** 정책 파일의 내용을 가지고 있는 문자열 */
		private var _policyStr:String;
		
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 타입 객체 */
		private var _socketSecurity:SocketSecurity;
		
		/** 정책 파일 전송용 서버 */
		public function TCPPolicyServer(serverAddress:String="0.0.0.0", serverPort:int=843, socketSecurity:SocketSecurity=null)
		{
			_socket = new ServerSocket();
			_address = serverAddress;
			_port = serverPort;
			_run = false;
			_runnedTime = -1;
			_record = new RecordConsole();
			_policyStr = "<?xml version='1.0'?><cross-domain-policy><allow-access-from domain='" + _address + "' to-ports='" + _port + "'/></cross-domain-policy>";
			
			if(socketSecurity == null)
			{
				socketSecurity = new SocketSecurity(false);
			}
			_socketSecurity = socketSecurity;
		}
		
		/** 플래시의 네이티브 소켓을 가져온다. */
		public function get serverSocket():ServerSocket
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
			
			_address =value;
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
			
			_port =value;
		}
		
		/** 통신이 허용 또는 비허용된 목록을 가지고 있는 SocketSecurity 객체를 가져오거나 설정한다. */
		public function get socketSecurity():SocketSecurity
		{
			return _socketSecurity;
		}
		public function set socketSecurity(value:SocketSecurity):void
		{
			_socketSecurity = value;
		}
		
		/** 서버가 실행 중인지를 나타내는 값을 가져온다. */
		public function get isRunning():Boolean
		{
			return _run;
		}
		
		/** 디버그용 기록을 가지고 있는 RecordConsole 객체를 가져온다. */
		public function get record():RecordConsole
		{
			return _record;
		}
		
		/** 서버가 시작된 후 시간이 얼마나 지났는지를 나타내는 Number 값을 가져온다.(ms) */
		public function get elapsedTimeAfterRun():Number
		{
			if(_run == false)
			{
				return -1;
			}
			
			return _runnedTime - getTimer();
		}
		
		public function dispose():void
		{
			_socket.close();
			_socket.removeEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.removeEventListener(Event.CLOSE, _close);
			_socket = null;
			_address = null;
			_record.dispose();
			_record = null;
			_socketSecurity.dispose();
			_socketSecurity = null;
		}
		
		/** 서버 작동 시작 */
		public function run():void
		{
			if(!_address || _run == true)
			{
				return;
			}
			
			_run = true;
			_runnedTime = getTimer();
			_socket.bind(_port, _address);
			_socket.listen();
			_socket.addEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.addEventListener(Event.CLOSE, _close);
			_record.addRecord(true, "Opened server(runnedTime:" + _runnedTime + ")");
		}
		
		/** 운영체제에 의해 소켓이 닫힘 */
		private function _close():void
		{
			_socket.close();
			_socket.removeEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.removeEventListener(Event.CLOSE, _close);
			
			_record.addRecord(true, "Closed server by OS(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")");
			_run = false;
			dispatchEvent(new GogduNetEvent(GogduNetEvent.CLOSE));
		}
		
		/** 서버 작동 중지 */
		public function close():void
		{
			if(_run == false)
			{
				return;
			}
			
			_socket.close();
			_socket.removeEventListener(ServerSocketConnectEvent.CONNECT, _socketConnect);
			_socket.removeEventListener(Event.CLOSE, _close);
			_socket = new ServerSocket(); //ServerSocket is non reusable after ServerSocket.close()
			
			_record.addRecord(true, "Closed server(elapsedTimeAfterRun:" + elapsedTimeAfterRun + ")");
			_run = false;
		}
		
		/** 클라이언트 접속 */
		private function _socketConnect(e:ServerSocketConnectEvent):void
		{
			var socket:Socket = e.socket as Socket;
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
				_record.addRecord(true, "Sensed unpermitted connection(address:" + socket.remoteAddress + 
					", port:" + socket.remotePort + ")");
				dispatchEvent( new GogduNetEvent(GogduNetEvent.UNPERMITTED_CONNECTION, false, false, {address:socket.remoteAddress, port:socket.remotePort}) );
				socket.close();
				return;
			}
			
			e.socket.addEventListener(ProgressEvent.SOCKET_DATA, _onSocketData);
			_record.addRecord(true, "Client connected(address:" + socket.remoteAddress + ", port:" + socket.remotePort + ")");
			dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CONNECT, false, false, {address:socket.remoteAddress, port:socket.remotePort}) );
		}
		
		private function _onSocketData(e:ProgressEvent):void
		{
			var socket:Socket = e.currentTarget as Socket;
			socket.removeEventListener(ProgressEvent.SOCKET_DATA, _onSocketData);
			
			//정책 파일의 내용을 가지고 있는 문자열을 전송
			socket.writeUTFBytes(_policyStr);
			socket.writeByte(0);
			socket.flush();
			
			//5초 뒤에 자동으로 소켓과의 연결을 끊는다.
			setTimeout(_closeSocket, 5000, socket);
			
			/*_record.addRecord(true, "Send policy file(address:" + socket.remoteAddress + ", port:" + socket.remotePort + ")");*/
		}
		
		/** 소켓의 연결을 끊음 */
		private function _closeSocket(socket:Socket):void
		{
			try
			{
				socket.close();
				dispatchEvent( new GogduNetEvent(GogduNetEvent.SOCKET_CLOSE, false, false, {address:socket.remoteAddress, port:socket.remotePort}) );
			}
			catch(e:Error)
			{
				_record.addErrorRecord(true, e, "It occurred from forced close connection");
			}
		}
	} // class
} // package