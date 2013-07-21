package gogduNet.connection
{
	import flash.events.EventDispatcher;
	
	/** 서버나 클라이언트 등, 통신 객체들의 최상위 클래스입니다. */
	public class ClientBase extends EventDispatcher
	{
		/** 패킷을 추출할 때 사용할 정규 표현식 */
		public static const EXTRACTION_REG_EXP:RegExp = /(?!\.)[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+\/=]+\./g;
		/** 필요 없는 패킷들을 제거할 때 사용할 정규 표현식 */
		public static const FILTER_REG_EXP:RegExp = /[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+\/=]*[^ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+\/\.=]+[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstupvxyz0123456789\+\/=]*|(?<=\.)\.+|(?<!.)\./g;
		
		/** Don't create this instance */
		public function ClientBase()
		{
		}
	}
}