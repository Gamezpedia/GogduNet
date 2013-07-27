package gogduNet.connection
{
	public class DataType
	{
		/** 아무것도 아닌 타입을 정의하는 상수입니다. */
		public static const INVALID:uint = 0;
		/** 라이브러리 내부에서 쓰이는 타입을 정의하는 상수입니다. */
		public static const SYSTEM:uint = 1;
		/** 데이터 부분 없이 def 정보만 있는 패킷의 타입을 정의하는 상수입니다. */
		public static const DEFINITION:uint = 2;
		/** boolean 타입 */
		public static const BOOLEAN:uint = 3;
		/** byte 타입 */
		public static const BYTE:uint = 4;
		/** ubyte 타입 */
		public static const UNSIGNED_BYTE:uint = 5;
		/** short 타입 */
		public static const SHORT:uint = 6;
		/** ushort 타입 */
		public static const UNSIGNED_SHORT:uint = 7;
		/** int 타입 */
		public static const INT:uint = 8;
		/** uint 타입 */
		public static const UNSIGNED_INT:uint = 9;
		/** float 타입 */
		public static const FLOAT:uint = 10;
		/** double 타입 */
		public static const DOUBLE:uint = 11;
		/** byte array 타입 */
		public static const BYTES:uint = 12;
		/** string 타입 */
		public static const STRING:uint = 13;
		/** array 타입 */
		public static const ARRAY:uint = 14;
		/** object 타입 */
		public static const OBJECT:uint = 15;
		
		/** Don't create instance of this class */
		public function DataType()
		{
			throw new Error("Don't create instance of this class");
		}
	}
}