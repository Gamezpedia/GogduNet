package gogduNet.connection
{
	import flash.utils.ByteArray;
	
	import gogduNet.utils.Base64;

	public class UnitedPacketNode
	{
		/** Don't create instance of this class */
		public function UnitedPacketNode()
		{
			throw new Error("Don't create instance of this class");
		}
		
		public static function create(type:uint, def:uint, data:ByteArray):Object
		{
			var obj:Object = {};
			obj.type = type;
			obj.def = def;
			
			var str:String = Base64.encode(data);
			obj.data = str;
			
			return obj;
		}
	}
}