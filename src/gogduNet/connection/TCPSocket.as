package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.ProgressEvent;
	import flash.net.Socket;
	import flash.utils.ByteArray;
	
	/** <p>비자발적으로 연결이 끊긴 경우 발생합니다.</p>
	 * <p>라이브러리 내부에서 사용되는 이벤트로서, 이 이벤트 대신
	 * TCPServer나 TCPBinaryServer의 GogduNetEvent.SOCKET_CLOSE 이벤트를 사용하는 것을 권장합니다.</p>
	 */
	[Event(name="close", type="flash.events.Event")]
	/** <p>라이브러리 내부에서 사용되는 이벤트로서, 이 이벤트 대신
	 * TCPServer나 TCPBinaryServer의 DataEvent 타입의 이벤트를 사용하는 것을 권장합니다.</p>
	 */
	[Event(name="socketData", type="flash.events.ProgressEvent")]
	
	public class TCPSocket extends SocketBase
	{
		private var _socket:Socket;
		private var __backupBuffer:ByteArray;
		private var __unitedBuffer:Vector.<Object>;
		
		/** 반드시 initialize() 함수를 실행하고 nativeSocket, id 속성을 설정해야 한다. */
		public function TCPSocket()
		{
		}
		
		override public function initialize():void
		{
			super.initialize();
			
			_socket = null;
			__backupBuffer = new ByteArray();
			__unitedBuffer = new <Object>[];
		}
		
		/** 플래시 네이티브 소켓을 가져온다. */
		public function get nativeSocket():Socket
		{
			return _socket;
		}
		/** 라이브러리 내부에서 자동으로 실행되는 함수 */
		internal function _setNativeSocket(value:Socket):void
		{
			if(_socket)
			{
				_socket.removeEventListener(Event.CLOSE, _onClose);
				_socket.removeEventListener(ProgressEvent.SOCKET_DATA, _onData);
			}
			
			_socket = value;
			_socket.addEventListener(Event.CLOSE, _onClose);
			_socket.addEventListener(ProgressEvent.SOCKET_DATA, _onData);
		}
		
		/** 이 소켓의 address를 가져온다. */
		public function get address():String
		{
			return _socket.remoteAddress;
		}
		
		/** 이 소켓의 포트를 가져온다. */
		public function get port():int
		{
			return _socket.remotePort;
		}
		
		/** 현재 연결되어 있는가를 나타내는 값을 가져온다. */
		public function get isConnected():Boolean
		{
			return _socket.connected;
		}
		
		/** 통신을 할 때 아직 처리하지 못 한 패킷을 보관하는 바이트 배열이다.
		 * (이 속성은 건드리지 않는 것이 좋다.)
		 */
		internal function get _backupBuffer():ByteArray
		{
			return __backupBuffer;
		}
		
		/** 패킷을 한 번에 뭉쳐서 보내기 위해 사용되는 배열 버퍼이며,
		 * 배열에 사용되는 Object 객체는 UnitedPacketNod.create()로 만들 수 있다.
		 * (이 속성은 건드리지 않는 것이 좋다.)
		 */
		internal function get _unitedBuffer():Vector.<Object>
		{
			return __unitedBuffer;
		}
		
		private function _onData(e:ProgressEvent):void
		{
			dispatchEvent(e);
		}
		
		private function _onClose(e:Event):void
		{
			dispatchEvent(e);
		}
		
		override public function dispose():void
		{
			super.dispose();
			
			_socket.removeEventListener(Event.CLOSE, _onClose);
			_socket.removeEventListener(ProgressEvent.SOCKET_DATA, _onData);
			_socket = null;
			__backupBuffer = null;
			__unitedBuffer = null;
		}
	}
}