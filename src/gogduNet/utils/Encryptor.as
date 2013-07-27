package gogduNet.utils
{
	import flash.utils.ByteArray;
	import flash.utils.CompressionAlgorithm;
	import gogduNet.connection.EncodingFormat;
	
	//import com.hurlant.crypto.symmetric.XTeaKey;
	//import com.hurlant.util.Hex;
	
	/** 이 클래스를 수정하여 패킷의 암호화 방법을 바꿀 수 있습니다. 단, 암호화의 최종 결과물은 Base64로 인코딩된 것이어야 합니다. */
	public class Encryptor
	{
		//public static var cipher:XTeaKey = new XTeaKey(Hex.toArray("809849497DF33CE3809849497DF33CE3809849497DF33CE3809849497DF33CE3809849497DF33CE3"));
		
		/** 바이트 배열을 압축+암호화하여 반환합니다.
		 * 실패하면 null을 반환합니다. */
		public static function encode(bytes:ByteArray):ByteArray
		{
			try
			{
				bytes.compress(CompressionAlgorithm.DEFLATE);
				//cipher.encrypt(bytes); //암호화
				//bytes.compress(CompressionAlgorithm.DEFLATE);
				
				return bytes;
			}
			catch(e:Error)
			{
				return null;
			}
			
			return null;
		}
		
		/** encode 함수로 압축+암호화한 바이트 배열을 다시 원래대로 되돌립니다.
		 * 실패하면 null을 반환합니다. */
        public static function decode(bytes:ByteArray):ByteArray
		{
			try
			{
				bytes.uncompress(CompressionAlgorithm.DEFLATE);
				//cipher.decrypt(bytes); //복호화
				//bytes.uncompress(CompressionAlgorithm.DEFLATE);
				
				return bytes;
			}
			catch(e:Error)
			{
				return null;
			}
			
			return null;
		}
	}
}