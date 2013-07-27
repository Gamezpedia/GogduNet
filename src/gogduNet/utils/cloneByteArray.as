package gogduNet.utils
{
	import flash.utils.ByteArray;
	
	public function cloneByteArray(bytes:ByteArray, result:ByteArray=null):ByteArray
	{
		if(result == null)
		{
			result = new ByteArray();
		}
		
		bytes.position = 0;
		bytes.readBytes(result);
		
		return result;
	}
}