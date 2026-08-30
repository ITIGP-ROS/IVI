"""Which sign cancels the ego yaw? Test both against parked-car heading spread."""
import math, time, statistics as st
from collections import defaultdict
import rclpy
from rclpy.node import Node
from object_detection_msgs.msg import Object3dArray
from nav_msgs.msg import Odometry

class W(Node):
    def __init__(self):
        super().__init__("check_sign")
        self.yaw = None; self.first = None
        self.d = defaultdict(list)
        self.create_subscription(Odometry, "/odom", self.odom, 10)
        self.create_subscription(Object3dArray, "/object_detections_3d", self.det, 10)
    def odom(self, m):
        q = m.pose.pose.orientation
        y = math.atan2(2*(q.w*q.z+q.x*q.y), 1-2*(q.y*q.y+q.z*q.z))
        if self.first is None: self.first = y
        self.yaw = math.degrees(y - self.first)
    def det(self, msg):
        if self.yaw is None: return
        for o in msg.objects:
            if o.label != 2: continue
            c = [(p.x, p.y) for p in o.bounding_box.corners]
            s = math.degrees(math.atan2(c[4][1]-c[0][1], c[4][0]-c[0][0]))
            self.d[o.track_id].append((s, self.yaw))

def spread(vals):
    base = vals[0]
    w = [(v-base+90) % 180 - 90 for v in vals]
    return max(w) - min(w)

rclpy.init(); n = W(); t = time.monotonic()
while time.monotonic() - t < 45: rclpy.spin_once(n, timeout_sec=0.1)
res = {"sensor (no correction)": [], "s + yaw": [], "s - yaw": []}
for tid, v in n.d.items():
    if len(v) < 25: continue
    res["sensor (no correction)"].append(spread([a for a, _ in v]))
    res["s + yaw"].append(spread([a + b for a, b in v]))
    res["s - yaw"].append(spread([a - b for a, b in v]))
for k, v in res.items():
    if v: print(f"  {k:24s} median {st.median(v):5.1f}d   worst {max(v):5.1f}d   (n={len(v)} tracks)")
rclpy.shutdown()
