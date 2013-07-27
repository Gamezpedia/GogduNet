package gogduNet.connection
{
	/** <p>라이브러리 내부에서 쓰이도록 할당된 Data Definition을 정의하는 상수들을 가지고 있는 클래스입니다.</p>
	 * <p>패킷을 보낼 때 Definition으로 여기에 정의된 것을 쓰지 마세요. (4 이상의 값을 쓰세요)</p>
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
		
		/** Don't create instance of this class */
		public function DataDefinition()
		{
			throw new Error("Don't create instance of this class");
		}
	}
}