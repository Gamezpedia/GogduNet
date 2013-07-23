/* made by Siyania (siyania@naver.com)(http://siyania.blog.me/) */
package gogduNet.connection
{
	import flash.events.EventDispatcher;
	
	/** This class is top-level class of Communication objects which such as Client and Server. */
	public class ClientBase extends EventDispatcher
	{
		/** Regular expression used when extracting packets. */
		public static const EXTRACTION_REG_EXP:RegExp = /(?!\.)[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+\/=]+\./g;
		/** Regular expression used when removing packets not required. */
		public static const FILTER_REG_EXP:RegExp = /[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+\/=]*[^ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+\/\.=]+[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+\/=]*|(?<=\.)\.+|(?<!.)\./g;
		
		/** Don't create this instance */
		public function ClientBase()
		{
		}
	}
}