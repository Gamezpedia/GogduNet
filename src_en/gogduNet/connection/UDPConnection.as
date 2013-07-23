package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.utils.ByteArray;
	
	public class UDPConnection extends SocketBase
	{
		private var _address:String;
		private var _port:int;
		private var _backupByteArray:ByteArray;
		
		/** 반드시 address, port 속성을 설정해야 한다. */
		public function UDPConnection()
		{
			initialize();
		}
		
		override public function initialize():void
		{
			super.initialize();
			
			_address = null;
			_port = 0;
			_backupByteArray = new ByteArray();
		}
		
		/** 대상의 address를 가져온다. */
		public function get address():String
		{
			return _address;
		}
		/** 라이브러리 내부에서 자동으로 실행되는 함수 */
		internal function _setAddress(value:String):void
		{
			_address = value;
		}
		
		/** 대상의 포트를 가져온다. */
		public function get port():int
		{
			return _port;
		}
		/** 라이브러리 내부에서 자동으로 실행되는 함수 */
		internal function _setPort(value:int):void
		{
			_port = value;
		}
		
		/** 통신을 할 때 아직 처리하지 못 한 패킷을 보관하는 바이트 배열이다.<p/>
		 * 배열이 수정되면 오류가 날 수 있으므로 건드리지 않는 것이 좋다.
		 */
		internal function get _backupBytes():ByteArray
		{
			return _backupByteArray;
		}
		
		override public function dispose():void
		{
			super.dispose();
			
			_address = null;
			_backupByteArray = null;
		}
	}
}