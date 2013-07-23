package gogduNet.utils
{
	import gogduNet.utils.Encryptor;
	import gogduNet.utils.parseData;
	
	/** 암호화된 상태인 한 개의 패킷(str)을 검사하여 정상적인 패킷이면 변환된 Object를, 문제가 있는 패킷이면 null을 반환합니다. */
	public function parsePacket(str:String):Object
	{
		str = str.replace(/.$/, "");
		
		try{str = Encryptor.decode(str);}
		catch(e:Error){return null;}
		
		var obj:Object;
		
		try{obj = JSON.parse(str);}
		catch(e:Error){return null;}
		
		if(!obj.t){return null;}
		if(!obj.df){return null;}
		
		if(obj.t != DataType.DEFINITION && !obj.dt){return null;}
		
		if(obj.t == DataType.DEFINITION)
		{
			return obj;
		}
		else
		{
			var data:Object = parseData(obj.t, obj.dt);
			
			if(data != null)
			{
				obj.data = data;
				return obj;
			}
			else
			{
				return null;
			}
		}
	}
}