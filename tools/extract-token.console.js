// PLAUD 토큰 자동 추출 (콘솔 버전)
//
// 사용법:
//   1) Chrome에서 https://web.plaud.ai 접속 + 로그인 + 메인 화면 도달
//   2) ⌘⌥I → Console 탭
//   3) 이 파일 내용을 콘솔에 붙여넣기 (Chrome 보안 경고 시 "Allow pasting" 입력)
//   4) Enter
//   5) 페이지를 한 번 클릭하거나 새로고침
//   6) 콘솔에 "✅ 토큰 클립보드 복사" 메시지 → 클립보드에 진짜 동작 토큰 복사됨
//
// 작동 방식:
//   - window.fetch와 XMLHttpRequest.setRequestHeader를 wrap해 첫 API 호출의
//     Authorization: Bearer ... 헤더를 가로챈다.
//   - 첫 토큰 캡처 후 원래 함수로 복원하고 자동으로 navigator.clipboard에 복사.
//   - 이렇게 하면 LocalStorage 캐시 문제와 무관하게 PLAUD Web이 실제로 사용 중인
//     토큰을 그대로 가져올 수 있다.

(() => {
    const origFetch = window.fetch;
    const origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
    let captured = false;

    const handle = async (token) => {
        if (captured) return;
        captured = true;
        // 원래 함수 복원
        window.fetch = origFetch;
        XMLHttpRequest.prototype.setRequestHeader = origSetHeader;

        try {
            await navigator.clipboard.writeText(token);
            console.log('%c✅ 토큰 클립보드 복사 완료 (' + token.length + '자)', 'color:#0a0;font-weight:bold');
            console.log('   preview: ' + token.slice(0, 20) + '...' + token.slice(-10));
            console.log('💡 터미널의 setup.sh 또는 npm run refresh-token 에서 Enter를 누르면 자동으로 사용됩니다.');
        } catch (e) {
            console.warn('⚠ 클립보드 자동 복사 실패. 다음 토큰을 직접 복사하세요:');
            console.warn(token);
        }
    };

    // fetch wrap
    window.fetch = function (input, init = {}) {
        if (init && init.headers) {
            try {
                const headers = new Headers(init.headers);
                const auth = headers.get('authorization') || headers.get('Authorization');
                if (auth && /^Bearer eyJ/i.test(auth)) {
                    handle(auth.replace(/^Bearer\s+/i, ''));
                }
            } catch (_) { /* ignore */ }
        }
        return origFetch.apply(this, arguments);
    };

    // XMLHttpRequest wrap (axios 등이 쓰는 경우 대비)
    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
        if (/^authorization$/i.test(name) && /^Bearer eyJ/i.test(String(value))) {
            handle(String(value).replace(/^Bearer\s+/i, ''));
        }
        return origSetHeader.apply(this, arguments);
    };

    console.log('%c🎣 PLAUD 토큰 인터셉트 활성화', 'color:#08f;font-weight:bold');
    console.log('   페이지를 한 번 클릭하거나 새로고침하세요.');
    console.log('   첫 API 호출의 토큰이 자동으로 클립보드에 복사됩니다.');
})();
