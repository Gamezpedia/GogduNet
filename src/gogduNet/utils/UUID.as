/* THANKS
actionscript-uuid
(https://code.google.com/p/actionscript-uuid/)
(yonghaolai6@gmail.com)
*/
package gogduNet.utils
{
	import flash.system.System;
	import flash.utils.ByteArray;
	import flash.utils.getTimer;
	
	public class UUID
	{
		// Char codes for 0123456789ABCDEF
		private static const ALPHA_CHAR_CODES:Array = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70];
		
		private static var _buff:ByteArray = new ByteArray;
		
		public static function create():String
		{
			var r:uint = uint(new Date().time);
			_buff.length = 0;
			_buff.writeUnsignedInt(System.totalMemory ^ r);
			_buff.writeInt(getTimer() ^ r);
			_buff.writeDouble(Math.random() * r);
			_buff.position = 0;
			
			var chars:Array = [36];
			var index:uint = 0;
			
			for (var i:uint = 0; i < 16; i++)
			{
				if (i == 4 || i == 6 || i == 8 || i == 10)
				{
					chars[index++] = 45; // Hyphen char code
				}
				var b:int = _buff.readByte();
				chars[index++] = ALPHA_CHAR_CODES[(b & 0xF0) >>> 4];
				chars[index++] = ALPHA_CHAR_CODES[(b & 0x0F)];
			}
			
			var str:String = String.fromCharCode.apply(null, chars);
			return str;
		}
	}
}