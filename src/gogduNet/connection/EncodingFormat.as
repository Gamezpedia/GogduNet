package gogduNet.connection
{
	public class EncodingFormat
	{
		/** 바이트를 문자열로 변환할 때 쓸 인코딩 포맷 형식입니다. */
		public static var encoding:String = "UTF-8";
		
		/** Don't create instance of this class */
		public function EncodingFormat()
		{
			throw new Error("Don't create instance of this class");
		}
	}
}