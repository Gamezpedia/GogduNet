package gogduNet.connection
{
	import flash.net.NetStream;
	import flash.utils.setTimeout;
	
	public class P2PPeer extends SocketBase
	{
		private var _netStream:NetStream;
		private var _peerStream:NetStream;
		
		private var _parent:P2PClient;
		
		/** Must set netStream and id attribute */
		public function P2PPeer()
		{
			initialize();
		}
		
		override public function initialize():void
		{
			super.initialize();
			
			_netStream = null;
			_peerStream = null;
			
			_parent = null;
		}
		
		/** 라이브러리 내부에서 자동으로 실행되는 함수 */
		internal function _setParent(value:P2PClient):void
		{
			_parent = value;
		}
		
		/** 이 객체 자신의 넷 스트림을 가져온다. */
		public function get netStream():NetStream
		{
			return _netStream;
		}
		/** 라이브러리 내부에서 자동으로 실행되는 함수 */
		internal function setNetStream(value:NetStream):void
		{
			_netStream = value;
		}
		
		/** 데이터 전송에 쓰는 스트림을 가져온다.<p/>
		 * 단, 연결한 후 스트림을 찾는 데에 시간이 걸리므로 연결 후 일정 시간 동안은 null값을 반환한다.<p/>
		 * (어도비의 Cirrus 서버의 상태가 좋지 않거나 인터넷 연결 상태가 매우 좋지 않으면 계속 null값을 반환할 수도 있다.)
		 */
		public function get peerStream():NetStream
		{
			if(!_peerStream)
			{
				_searchForPeerStream(1);
			}
			
			if(_peerStream)
			{
				return _peerStream;
			}
			
			return null;
		}
		
		/** 이 피어의 피어 ID를 가지고 온다. (id ≠ peerID) */
		public function get peerID():String
		{
			if(!_netStream)
			{
				return null;
			}
			
			return _netStream.farID;
		}
		
		/** 보안상 수신한 peerID를 쓰지 않고 직접 여기서 peerID를 얻어 쓰기 위해 한 번 거쳐 간다. */
		internal function _getData(jsonStr:String):void
		{
			_parent._getData(id, jsonStr);
		}
		
		/** <p>(라이브러리 내부에서 자동으로 실행되는 함수)<p/>
		 * 자신의 데이터 전송용 스트림을 찾아서 peerStream 함수의 반환값으로 설정합니다.
		 * 연결 직후 자동으로 이 함수가 실행되나, 불안정한 연결 때문에 찾는 데에 약간의 시간이 걸립니다.</p>
		 * <p>findStream 인수는 자신의 전송용 스트림을 찾기 위해 peerStreams 속성을 가져올 스트림입니다.</p>
		 * <p>tryNum 인수는 몇 번 탐색을 시도할 것인지를 설정합니다. tryNum 인수만큼 시도해도 찾을 수 없으면 탐색을 중단합니다.</p>
		 * <p>tryInterval 인수는 탐색을 시도하는 간격을 설정합니다.</p>
		 */
		internal function _searchForPeerStream(tryNum:int=50, tryInterval:Number=100):void
		{
			var i:int;
			var stream:NetStream = _parent.getPeerStream(peerID);
			
			if(stream)
			{
				_peerStream = stream;
			}
			else
			{
				tryNum -= 1;
				
				if(tryNum <= 0)
				{
					return;
				}
				else
				{
					setTimeout(_searchForPeerStream, tryInterval, tryNum, tryInterval);
				}
			}
		}
		
		override public function dispose():void
		{
			super.dispose();
			
			if(_netStream){_netStream.dispose();}
			_netStream = null;
			
			if(_peerStream){_peerStream.dispose();}
			_peerStream = null;
			
			_parent = null;
		}
	}
}