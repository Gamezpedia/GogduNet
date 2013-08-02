package gogduNet.connection
{
	import flash.utils.ByteArray;
	
	import gogduNet.utils.Base64;

	public class ParsedNode
	{
		public static const INVALID_EVENT:String = "invalidEvent";
		public static const RECEIVE_EVENT:String = "receiveEvent";
		
		/** Don't create instance of this class */
		public function ParsedNode()
		{
			throw new Error("Don't create instance of this class");
		}
		
		/** packetInfo = {type, def, data} */
		public static function create(event:String, type:uint, def:uint, data:Object):Object
		{
			var obj:Object = {};
			obj.event = event;
			
			var packetObj:Object = {};
			packetObj.type = type;
			packetObj.def = def;
			packetObj.data = data;
			
			obj.packet = packetObj;
			
			return obj;
		}
	}
}