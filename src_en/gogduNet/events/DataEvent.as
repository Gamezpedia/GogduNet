package gogduNet.events
{
	import flash.events.Event;
	
	public class DataEvent extends Event
	{
		/** 데이터를 완전히 전송 받은 경우 발생하는 이벤트의 타입 상수 */
		public static const RECEIVE_DATA:String = "receiveData";
		/** 잘못된 패킷을 전송 받은 경우에 발생하는 이벤트의 타입 상수 */
		public static const INVALID_PACKET:String = "invalidPacket";
		
		/** 데이터를 전송 받는 중일 때 발생하는 이벤트의 타입 상수 */
		public static const PROGRESS_DATA:String = "progressData";
		
		private var _socketID:String;
		private var _dataType:String;
		private var _dataDefinition:String;
		private var _data:Object;
		
		public function DataEvent(eventType:String, bubbles:Boolean=false, cancelable:Boolean=false,
										socketID:String=null, dataType:String=null, dataDefinition:String=null, data:Object=null)
		{
			super(eventType, bubbles, cancelable);
			_socketID = socketID;
			_dataType = dataType;
			_dataDefinition = dataDefinition;
			_data = data;
		}
		
		/** 소켓의 식별 id (UUID) */
		public function get socketID():String
		{
			return _socketID;
		}
		
		/** 데이터의 타입. DataType에 상수로 정의되어 있다. */
		public function get dataType():String
		{
			return _dataType;
		}
		
		/** 데이터의 Definition */
		public function get dataDefinition():String
		{
			return _dataDefinition;
		}
		
		/** 실질적 데이터 */
		public function get data():Object
		{
			return _data;
		}
		
		override public function clone():Event
		{
			return new DataEvent(type, bubbles, cancelable, _socketID, _dataType, _dataDefinition, _data);
		}
	}
}