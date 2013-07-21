package gogduNet.utils
{
	public class DataType
	{
		/** 잘못된 패킷의 타입을 정의하는 상수 */
		public static const INVALID:String = "invalid";
		
		/** 데이터 부분이 없이 프로토콜 정의만 있는 패킷의 타입을 정의하는 상수 */
		public static const DEFINITION:String = "def";
		/** 문자열 정보를 가진 패킷의 타입을 정의하는 상수 */
		public static const STRING:String = "str";
		/** 배열 정보를 가진 패킷의 타입을 정의하는 상수 */
		public static const ARRAY:String = "arr";
		/** int 정수 정보를 가진 패킷의 타입을 정의하는 상수 */
		public static const INTEGER:String = "int";
		/** uint 정수 정보를 가진 패킷의 타입을 정의하는 상수 */
		public static const UNSIGNED_INTEGER:String = "uint";
		/** Number 소수 정보를 가진 패킷의 타입을 정의하는 상수 */
		public static const RATIONALS:String = "rati";
		/** 참/거짓 정보를 가진 패킷의 타입을 정의하는 상수 */
		public static const BOOLEAN:String = "tf";
		/** JSON 오브젝트 정보를 가진 패킷의 타입을 정의하는 상수 */
		public static const JSON:String = "json";
		
		/** 바이트 정보를 가진 패킷의 타입을 정의하는 상수.
		 * GogduNetBinaryServer과 GogduNetBinaryClient에서만 쓰인다.
		 */
		public static const BYTES:String = "bts";
		
		/** Don't create this instance */
		public function DataType()
		{
			throw new Error("DataType 클래스는 인스턴스 객체를 생성할 수 없습니다.");
		}
	}
}