import os
import sys
import pty
import select
import tty
import termios
import threading
import time
import json
import signal
import fcntl
from queue import Queue, Empty
from urllib.request import Request, urlopen

# Configuration
ROUTER_URL = os.environ.get("ROUTER_URL", "http://127.0.0.1:8765")
POLL_INTERVAL = 3.0  # 更快轮询
HEARTBEAT_INTERVAL = 30.0
ROUTER_WAIT_TIMEOUT = 30
# 不再需要等待空闲和冷却时间，因为 Codex 支持 mid-turn 消息


def wait_for_router(timeout=ROUTER_WAIT_TIMEOUT):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            req = Request(f"{ROUTER_URL}/health", method="GET")
            with urlopen(req, timeout=2) as res:
                if res.status == 200:
                    return True
        except:
            pass
        time.sleep(0.5)
    return False


def register_presence(agent_id, role):
    url = f"{ROUTER_URL}/presence/register"
    payload = json.dumps({"agent": agent_id, "meta": {"role": role}}, ensure_ascii=False).encode('utf-8')
    try:
        req = Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        with urlopen(req, timeout=5) as res:
            return json.loads(res.read())
    except:
        return {}


def send_heartbeat(agent_id):
    url = f"{ROUTER_URL}/presence/heartbeat"
    payload = json.dumps({"agent": agent_id}).encode('utf-8')
    try:
        req = Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        urlopen(req, timeout=5)
    except:
        pass


def fetch_inbox(agent_id):
    url = f"{ROUTER_URL}/inbox?agent={agent_id}&limit=1"
    try:
        req = Request(url, method="GET")
        with urlopen(req, timeout=5) as res:
            data = json.loads(res.read())
            return data.get("messages", [])
    except:
        return []


def send_ack(agent_id, message_id, status="accepted"):
    """发送 ACK 给 Router，确认消息已处理，防止重试投递。"""
    url = f"{ROUTER_URL}/message"
    payload = json.dumps({
        "type": "ack",
        "ack_stage": status,
        "corr_id": message_id,
        "from": agent_id
    }).encode('utf-8')
    try:
        req = Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        urlopen(req, timeout=5)
        return True
    except:
        return False



def format_message(msg, role):
    """Format message with reply instructions."""
    sender = msg.get("from", "?")
    msg_id = msg.get("id", "")
    body = msg.get("body", "")
    
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except:
            pass
    
    if isinstance(body, dict):
        content = body.get("question", "") or body.get("message", "") or str(body)
    else:
        content = str(body)
    
    # 判断是否是确认类消息（不需要回复）
    confirm_keywords = ["收到", "等待", "待命", "已就绪", "继续等待", "请等待", "好的", "明白"]
    is_confirm_msg = any(kw in content for kw in confirm_keywords) and len(content) < 100
    
    # 构造回复命令示例
    reply_cmd = f"python3 $TEAM_TOOL say --from {role} --to {sender} --text \"你的回复\""
    
    if is_confirm_msg:
        # 确认类消息：不显示回复提示
        return f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
来自 [{sender}] 的消息：
{content}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
    else:
        # 需要处理的消息：只提醒命令，不强制回复
        return f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
来自 [{sender}] 的消息：
{content}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
回复命令备忘：{reply_cmd}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""








class ProxyState:
    def __init__(self):
        self.lock = threading.Lock()
        self.message_queue = Queue()  # 消息队列
    
    def update_output_time(self):
        # 保留接口，但不再用于等待判断
        pass


class OutputInterceptor:
    def __init__(self, master_fd, state):
        self.master_fd = master_fd
        self.state = state

    def write_to_agent(self, text):
        """Inject text and press Enter (Ctrl+M = 0x0D)."""
        text = text.strip()
        # 发送文本
        os.write(self.master_fd, text.encode('utf-8'))
        # 等一下让文本显示
        time.sleep(0.3)
        # 发送 Ctrl+M (0x0D) - 这是键盘回车键发送的实际字符
        os.write(self.master_fd, bytes([0x0D]))




def message_fetcher(state, agent_id, role, stop_event):
    """Thread 1: Fetch messages from router and put in queue."""
    if not wait_for_router():
        print(f"[Proxy] Router 不可用")
        return
    
    register_presence(agent_id, role)
    print(f"[Proxy] 已连接 Router，角色: {role}\n")
    
    seen_ids = set()
    last_heartbeat = time.time()
    
    while not stop_event.is_set():
        try:
            now = time.time()
            if now - last_heartbeat >= HEARTBEAT_INTERVAL:
                send_heartbeat(agent_id)
                last_heartbeat = now
            
            # 直接获取消息，不再判断是否空闲
            messages = fetch_inbox(agent_id)
            for msg in messages:
                msg_id = msg.get("id")
                if msg_id and msg_id not in seen_ids:
                    sender = msg.get("from", "")
                    if sender != role:  # 忽略自己的消息
                        seen_ids.add(msg_id)
                        state.message_queue.put(msg)
                        print(f"[Proxy] 收到来自 {sender} 的消息")
        except:
            pass
        
        time.sleep(POLL_INTERVAL)


def message_processor(interceptor, state, role, agent_id, stop_event):
    """Thread 2: Process messages - 直接发送，不等待空闲"""
    while not stop_event.is_set():
        try:
            # 从队列获取消息（阻塞等待，超时1秒）
            try:
                msg = state.message_queue.get(timeout=1)
            except Empty:
                continue
            
            msg_id = msg.get("id", "")
            sender = msg.get("from", "?")
            
            # 直接注入消息（Codex 支持 mid-turn）
            prompt = format_message(msg, role)
            print(f"[Proxy] 发送消息 (来自 {sender})")
            interceptor.write_to_agent(prompt)
            
            # 发送 ACK 给 Router
            if msg_id:
                send_ack(agent_id, msg_id, "accepted")
            
            # 短暂等待，避免消息堆积太快
            time.sleep(0.5)
            
            state.message_queue.task_done()
            
        except Exception as e:
            print(f"[Proxy] 错误: {e}")
            time.sleep(1)



def main():
    if len(sys.argv) < 2 or '--' not in sys.argv:
        print("Usage: python3 shell_proxy.py -- <command>")
        sys.exit(1)

    sep = sys.argv.index('--')
    cmd = sys.argv[sep + 1:]
    if not cmd:
        sys.exit(1)

    agent_id = os.environ.get("TEAM_AGENT_ID", "UNKNOWN")
    role = os.environ.get("TEAM_ROLE", "AGENT")
    
    print(f"[Proxy] 启动: {role} ({agent_id})")
    
    # 打印关键环境变量以供调试
    team_tool = os.environ.get("TEAM_TOOL", "未设置")
    print(f"[Proxy] TEAM_TOOL: {team_tool}")

    pid, master_fd = pty.fork()

    if pid == 0:
        # 子进程：启动 Codex
        # 确保环境变量被继承
        os.execvp(cmd[0], cmd)
    else:
        state = ProxyState()
        interceptor = OutputInterceptor(master_fd, state)
        stop_event = threading.Event()

        # Thread 1: Fetch messages
        t1 = threading.Thread(target=message_fetcher, args=(state, agent_id, role, stop_event), daemon=True)
        t1.start()
        
        # Thread 2: Process messages (one at a time)
        t2 = threading.Thread(target=message_processor, args=(interceptor, state, role, agent_id, stop_event), daemon=True)
        t2.start()


        def resize():
            try:
                ws = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, b'\x00' * 8)
                fcntl.ioctl(master_fd, termios.TIOCSWINSZ, ws)
            except:
                pass
        
        signal.signal(signal.SIGWINCH, lambda s, f: resize())
        resize()

        try:
            old_tty = termios.tcgetattr(sys.stdin)
            tty.setraw(sys.stdin.fileno())
            
            try:
                while True:
                    r, _, _ = select.select([sys.stdin, master_fd], [], [], 0.1)
                    
                    if sys.stdin in r:
                        d = os.read(sys.stdin.fileno(), 10240)
                        if not d: break
                        os.write(master_fd, d)
                    
                    if master_fd in r:
                        try:
                            o = os.read(master_fd, 10240)
                            if not o: break
                            os.write(sys.stdout.fileno(), o)
                            state.update_output_time()
                        except OSError:
                            break
            except:
                pass
            finally:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_tty)
                stop_event.set()
        except Exception as e:
            stop_event.set()


if __name__ == "__main__":
    main()
