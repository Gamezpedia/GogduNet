package gogduNet.connection
{
	import flash.events.EventDispatcher;
	import flash.utils.getTimer;
	
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.UUID;
	
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	
	/** 복수의 상대와 연결하는 클래스에서, 각각의 연결을 저장하는 객체들의 최상위 클래스입니다. */
	public class SocketBase extends EventDispatcher
	{
		/** 식별용 문자열 (UUID) */
		private var _id:String;
		private var _lastReceivedTime:Number;
		
		/** GogduNetEvent.CONNECTION_UPDATE 이벤트 객체 */
		private var _event:GogduNetEvent;
		
		/** Don't create this instance */
		public function SocketBase()
		{
		}
		
		public function initialize():void
		{
			_id = UUID.create();
			_lastReceivedTime = -1;
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
		}
		
		/** 개체 식별용 문자열 (UUID)
		 * (이 id와 P2PPeer 객체의 peerID는 다르다.)*/
		public function get id():String
		{
			return _id;
		}
		
		/** 마지막으로 연결된 시각으로부터 지난 시간을 가져온다.(ms) */
		public function get elapsedTimeAfterLastReceived():Number
		{
			return getTimer() - _lastReceivedTime;
		}
		
		/** 마지막으로 연결된 시각을 갱신한다.
		 * 서버가 이 소켓에게서 패킷을 받을 경우, 자동으로 이 함수가 실행되어 갱신된다.
		 * (서버가 이 소켓에게 패킷을 보낸 경우는 갱신되지 않는다.)
		 */
		public function updateLastReceivedTime():void
		{
			_lastReceivedTime = getTimer();
			dispatchEvent(_event);
		}
		
		public function dispose():void
		{
			_id = null;
			_event = null;
		}
	}
}