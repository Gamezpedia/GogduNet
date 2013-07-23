package gogduNet.connection
{
	import flash.events.EventDispatcher;
	import flash.utils.getTimer;
	
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.UUID;
	
	/** This occurs when update connection. (When receive data) */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	
	/** In class which to connect with multiple clients, top-level class of objects which handle each connection */
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
			_id = UUID.get();
			_lastReceivedTime = -1;
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
		}
		
		/** 개체 식별용 문자열 (UUID)
		 * (이 id와 P2PPeer 객체의 peerID는 다르다.)*/
		public function get id():String
		{
			return _id;
		}
		
		/** Get elapsed time after last received.(ms) */
		public function get elapsedTimeAfterLastReceived():Number
		{
			return getTimer() - _lastReceivedTime;
		}
		
		/** Update last received time.
		 * Automatically updates by execute this function when server received data from this socket.<p/>
		 * (Does not automatically update when server sends data to this socket)
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