package gogduNet.connection
{
	/** <p>라이브러리 내부에서 쓰이도록 할당된 Data Definition을 정의하는 상수들을 가지고 있는 클래스입니다.</p>
	 * <p>여기서 정의된 것들과의 충돌을 피하려면,
	 * DataEvent.DATA_RECEIVE 이벤트를 사용할 때 항상 dataDefinition 속성 뿐만 아니라 dataType 속성도 같이 확인하여
	 * 이벤트의 dataType 속성이 DataType.SYSTEM이 아닌 것만 사용하세요.</p>
	 */
	public class DataDefinition
	{
		/** 아무것도 아님을 정의합니다. */
		public static const INVALID:uint = 0;
		/** 클라이언트에게 접속이 성공했음을 알리는 패킷의 def을 정의합니다. */
		public static const CONNECT_SUCCESS:uint = 1;
		/** 클라이언트에게 접속이 실패했음을 알리는 패킷의 def을 정의합니다. */
		public static const CONNECT_FAIL:uint = 2;
		/** 클라이언트에게 연결이 끊겼음을 알리는 패킷의 def을 정의합니다. */
		public static const DISCONNECT:uint = 3;
		/** 뭉쳐진 패킷 */
		public static const UNITED_PACKET:uint = 4;
		
		/** Don't create instance of this class */
		public function DataDefinition()
		{
			throw new Error("Don't create instance of this class");
		}
	}
}