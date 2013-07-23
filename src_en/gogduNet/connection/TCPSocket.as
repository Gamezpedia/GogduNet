package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.net.Socket;
	import flash.utils.ByteArray;
	
	/** This occurs when involuntary closed connection.<p/>
	 * Because this event is used within the library,
	 * please use GogduNetEvent.SOCKET_CLOSE event in TCPServer class or TCPBinaryServer class
	 * instead of this event.
	 */
	[Event(name="close", type="flash.events.Event")]
	
	public class TCPSocket extends SocketBase
	{
		private var _socket:Socket;
		private var _backupByteArray:ByteArray;
		
		/** Must set nativeSocket and id attribute */
		public function TCPSocket()
		{
			initialize();
		}
		
		override public function initialize():void
		{
			super.initialize();
			
			_socket = null;
			_backupByteArray = new ByteArray();
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
			}
			
			_socket = value;
			_socket.addEventListener(Event.CLOSE, _onClose);
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
		 * 배열이 수정되면 오류가 날 수 있으므로 건드리지 않는 것이 좋다.
		 */
		internal function get _backupBytes():ByteArray
		{
			return _backupByteArray;
		}
		
		private function _onClose(e:Event):void
		{
			dispatchEvent(e);
		}
		
		override public function dispose():void
		{
			super.dispose();
			
			_socket.removeEventListener(Event.CLOSE, _onClose);
			_socket = null;
			_backupByteArray = null;
		}
	}
}