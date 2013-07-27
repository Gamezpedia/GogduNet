package gogduNet.utils
{
	import flash.utils.ByteArray;
	
	/** deleteCount가 0이면 startIndex부터의 모든 데이터를 지운다. */
	public function spliceByteArray(bytes:ByteArray, startIndex:uint, deleteCount:uint=0):void
	{
		bytes.position = 0;
		
		if(startIndex > bytes.length)
		{
			startIndex = bytes.length;
		}
		
		if(deleteCount == 0)
		{
			var offset:uint = 0;
		}
		else
		{
			offset = startIndex + deleteCount;
			
			if(offset > bytes.length)
			{
				offset = bytes.length;
			}
		}
		
		var result:ByteArray = new ByteArray();
		if(startIndex != 0)
		{
			result.writeBytes(bytes, 0, startIndex);
		}
		if(offset != 0)
		{
			result.writeBytes(bytes, offset);
		}
		
		bytes.clear();
		
		bytes.writeBytes(result);
	}
}