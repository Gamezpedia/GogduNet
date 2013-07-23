package gogduNet.events
{
	import flash.events.Event;
	
	public class GogduNetEvent extends Event
	{
		/** 연결이 갱신(정보를 수신)된 경우 발생하는 이벤트의 타입 상수 */
		public static const CONNECTION_UPDATE:String = "connectionUpdate";
		
		/** 허용되지 않은 연결이 감지되면 발생하는 이벤트의 상수 */
		public static const UNPERMITTED_CONNECTION:String = "unpermittedConnection";
		
		/** 소켓이 서버에 접속하면 발생하는 이벤트의 상수. */
		public static const SOCKET_CONNECT:String = "socketConnect";
		/** 소켓이 서버에 접속을 시도하였으나 실패한 경우에 발생하는 이벤트의 상수 */
		public static const SOCKET_CONNECT_FAIL:String = "socketConnectFail";
		/** 소켓과의 연결이 비자발적으로 끊긴 경우에 발생하는 이벤트의 상수.
		 * 소켓 측에서 연결을 끊었거나 오랜 시간 통신이 되지 않아 서버에서 자동으로 연결을 끊은 경우에 발생한다. */
		public static const SOCKET_CLOSE:String = "socketClose";
		
		/** 연결에 성곤한 경우 발생하는 이벤트의 상수 */
		public static const CONNECT:String = "connect";
		/** 연결이 끊긴 경우 발생하는 이벤트의 상수 */
		public static const CLOSE:String = "close";
		/** 클라이언트가 서버와의 연결에 실패한 경우 발생하는 이벤트의 상수 */
		public static const CONNECT_FAIL:String = "connectFail";
		
		private var _data:Object;
		
		public function GogduNetEvent(eventType:String, bubbles:Boolean=false, cancelable:Boolean=false,
										data:Object=null)
		{
			super(eventType, bubbles, cancelable);
			_data = data;
		}
		
		public function get data():Object
		{
			return _data;
		}
		
		override public function clone():Event
		{
			return new GogduNetEvent(type, bubbles, cancelable, _data);
		}
	}
}