package gogduNet.events
{
	import flash.events.Event;
	
	public class DataEvent extends Event
	{
		/** 데이터를 완전히 전송 받은 경우 발생하는 이벤트의 타입 상수 */
		public static const DATA_RECEIVE:String = "dataReceive";
		/** 잘못된 패킷을 전송 받은 경우에 발생하는 이벤트의 타입 상수 */
		public static const INVALID_DATA:String = "invalidData";
		
		/** 데이터를 받으면 발생하는 이벤트의 타입 상수 */
		public static const DATA_COME:String = "dataCome";
		
		private var _socketID:String;
		private var _dataType:uint;
		private var _dataDefinition:uint;
		private var _data:Object;
		
		public function DataEvent(eventType:String, bubbles:Boolean=false, cancelable:Boolean=false,
										socketID:String=null, dataType:uint=0, dataDefinition:uint=0, data:Object=null)
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
		public function get dataType():uint
		{
			return _dataType;
		}
		
		/** 데이터의 Definition */
		public function get dataDefinition():uint
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