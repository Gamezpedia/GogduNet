package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.utils.ByteArray;
	
	public class UDPConnection extends SocketBase
	{
		private var _address:String;
		private var _port:int;
		
		/** 반드시 initialize() 함수를 실행하고 address, port 속성을 설정해야 한다. */
		public function UDPConnection()
		{
		}
		
		override public function initialize():void
		{
			super.initialize();
			
			_address = null;
			_port = 0;
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
		
		override public function dispose():void
		{
			super.dispose();
			
			_address = null;
		}
	}
}