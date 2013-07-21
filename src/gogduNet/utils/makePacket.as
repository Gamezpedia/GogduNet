package gogduNet.utils
{
	import gogduNet.utils.Encryptor;
	
	/** 인자로 주어진 type과 definition, datas로 패킷 문자열을 만들어 반환한다. 단, 실패한 경우엔 null을 반환한다. */
	public function makePacket(type:String, definition:String, data:Object=null):String
	{
		try
		{
			var obj:Object;
			if(data == null)
			{
				obj = {t:type, df:definition};
			}
			else
			{
				obj = {t:type, df:definition, dt:data};
			}
			
			var str:String = JSON.stringify(obj);
			str = Encryptor.encode(str) + ".";
			
			return str;
		}
		catch(e:Error)
		{
			return null;
		}
		
		return null;
	}
}