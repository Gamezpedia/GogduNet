GogduNet
=====

**GogduNet** - Flash AS3 Communication Library for **TCP** and **UDP** and **P2P**

Automatic packet filtering, packet united sending, connection management, etc.

Version 4.0 (2013.8.3.)

Made by **Siyania**
(siyania@naver.com)
(http://siyania.blog.me/)

GogduNet을 사용하면 몇 줄의 코드만으로 간단하게 서버나 클라이언트를 만들 수 있으며, 자동으로 잘못된 패킷을 걸러 내고, 데이터를 패킷 단위로 구분하여 사용자에게 알려 줍니다. 또한, 데이터 사용량을 줄이기 위해 패킷을 뭉쳐 보내는 기능을 지원하며, 알아서 연결을 관리해 주고, 내부적으로 비동기(async) 처리와 Object Pool을 사용합니다.

Packet Filtering
-----
비정상적인 패킷을 걸러 내는 기능입니다. 후보 찾기식 검사 방법으로, 형식이 맞지 않거나 데이터가 잘못된 패킷과 정상적인 패킷을 구분하여 이벤트로 알려 줍니다.

http://siyania.blog.me/192381011

Packet United Sending
-----
P2PClient와 TCPClient, TCPServer에서 지원하는 기능입니다. send 함수 실행 시에 패킷을 바로 전송하지 않고, 내부 버퍼에 전송이 요청된 데이터들을 저장해 두었다가 일정 시간(unitedSendingInterval 속성)이 지날 때마다 버퍼에 데이터가 있는지 검사하여 데이터가 있으면 데이터들을 뭉쳐 하나의 패킷으로 만든 뒤 전송하는 기능이며, 패킷을 여러 개로 각각 전송하는 것에 비해 헤더 사용을 줄이고 한 번에 전송하는 크기가 커 압축 효과이 좋으므로 데이터 사용량을 크게 줄일 수 있습니다.

send 함수들(sendInt, sendString ...)의 마지막 unity:Boolean 인자를 true로 넣고 사용하면 이 기능을 활용할 수 잇으며, 내부에 저장된 버퍼를 뭉쳐서 전송하는 시간 간격은 각 클래스의 unitedSendingInterval 속성으로 설정할 수 있습니다.(기본값은 100(ms))

http://siyania.blog.me/192461307

Structure
-----
![My image](GogduNet.png)


-----
TCPServer : AIR 3.0 Desktop, AIR 3.8

TCPClient : Flash Player 11, AIR 3.0

TCPPolicyServer : AIR 3.0 Desktop, AIR 3.8

TCPBinaryServer : AIR 3.0 Desktop, AIR 3.8

TCPBinaryClient : Flash Player 11, AIR 3.0

UDPClient : AIR 3.0 Desktop, AIR 3.8

P2PClient : Flash Player 11, AIR 3.0


-----
Use actionscript-uuid

https://code.google.com/p/actionscript-uuid/

yonghaolai6@gmail.com