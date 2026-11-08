import urllib.request
import json
import time

def eval_script(script):
    url = 'http://127.0.0.1:9527/api/eval'
    data = json.dumps({'script': script}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        if res.get('success'):
            try:
                return json.loads(res.get('result', '{}'))
            except:
                return res.get('result')
        return res

# 探查页面滚动的实际表现
# 1. 查看当前页面的滚动高度与作品链接数
info1 = eval_script("""
(() => {
  return {
    scrollY: window.scrollY,
    scrollHeight: document.documentElement.scrollHeight,
    bodyHeight: document.body.scrollHeight,
    postCount: (document.querySelectorAll('[data-e2e="user-post-list"] a, ul[data-e2e="scroll-list"] a')).length
  };
})()
""")
print("滚动前状态:", info1)

# 2. 执行平滑滚动到底部
eval_script("""
(() => {
  window.scrollTo(0, document.documentElement.scrollHeight);
  window.dispatchEvent(new Event('scroll'));
  // 有些页面挂在 document.body 或特定滚动容器
  var scrollList = document.querySelector('[data-e2e="user-post-list"]') || document.querySelector('ul[data-e2e="scroll-list"]');
  if (scrollList) {
    scrollList.scrollTop = scrollList.scrollHeight;
    scrollList.dispatchEvent(new Event('scroll'));
  }
  return 'scrolled';
})()
""")

print("等待 2 秒观察是否触发新作品加载...")
time.sleep(2.5)

info2 = eval_script("""
(() => {
  return {
    scrollY: window.scrollY,
    scrollHeight: document.documentElement.scrollHeight,
    postCount: (document.querySelectorAll('[data-e2e="user-post-list"] a, ul[data-e2e="scroll-list"] a')).length
  };
})()
""")
print("滚动后状态:", info2)
