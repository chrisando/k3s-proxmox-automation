#!/usr/bin/env python3
"""Generate dark-mode PNG architecture diagrams for the k3s-ansible project."""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

# ── Colour palette ────────────────────────────────────────────────────────────
BG       = "#0d1117"   # page background
BOX_DARK = "#161b22"   # box fill (dark)
BOX_MED  = "#1f2937"   # slightly lighter box
BOX_ACCENT = "#1e3a5f" # blue-tinted box
BOX_PURPLE = "#2d1b4e" # purple-tinted box
BOX_GREEN  = "#1a3a2a" # green-tinted box
BOX_ORANGE = "#3a2a1a" # orange-tinted box
BOX_RED    = "#3a1a1a" # red-tinted box
BOX_TEAL   = "#1a3a3a" # teal-tinted box

BORDER_BLUE   = "#58a6ff"
BORDER_GREEN  = "#3fb950"
BORDER_PURPLE = "#bc8cff"
BORDER_ORANGE = "#e3b341"
BORDER_RED    = "#f85149"
BORDER_TEAL   = "#39d0d8"
BORDER_GREY   = "#484f58"

TEXT_PRIMARY   = "#e6edf3"
TEXT_SECONDARY = "#8b949e"
TEXT_BLUE      = "#79c0ff"
TEXT_GREEN     = "#7ee787"
TEXT_PURPLE    = "#d2a8ff"
TEXT_ORANGE    = "#ffa657"
TEXT_RED       = "#ff7b72"
TEXT_TEAL      = "#56d364"
TEXT_YELLOW    = "#e3b341"

ARROW_COLOR = "#484f58"


def new_fig(w, h):
    fig, ax = plt.subplots(figsize=(w, h))
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)
    ax.set_xlim(0, w)
    ax.set_ylim(0, h)
    ax.axis("off")
    return fig, ax


def box(ax, x, y, w, h, label, sublabel=None,
        fill=BOX_DARK, edge=BORDER_GREY, lw=1.5,
        label_color=TEXT_PRIMARY, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=7.5, radius=0.25):
    rect = FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f"round,pad=0,rounding_size={radius}",
        facecolor=fill, edgecolor=edge, linewidth=lw,
        zorder=2,
    )
    ax.add_patch(rect)
    cy = y + h / 2
    if sublabel:
        ax.text(x + w / 2, cy + h * 0.14, label,
                ha="center", va="center", fontsize=label_size,
                color=label_color, fontweight="bold", zorder=3)
        for i, line in enumerate(sublabel.split("\n")):
            ax.text(x + w / 2, cy - h * 0.12 - i * h * 0.12, line,
                    ha="center", va="center", fontsize=sub_size,
                    color=sub_color, zorder=3)
    else:
        ax.text(x + w / 2, cy, label,
                ha="center", va="center", fontsize=label_size,
                color=label_color, fontweight="bold", zorder=3)


def arrow(ax, x1, y1, x2, y2, label=None, color=ARROW_COLOR,
          label_color=TEXT_SECONDARY, lw=1.5, style="->",
          label_size=7.5, connectionstyle="arc3,rad=0"):
    ax.annotate(
        "", xy=(x2, y2), xytext=(x1, y1),
        arrowprops=dict(
            arrowstyle=style, color=color, lw=lw,
            connectionstyle=connectionstyle,
        ),
        zorder=4,
    )
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx + 0.05, my, label, ha="left", va="center",
                fontsize=label_size, color=label_color, zorder=5)


def hline(ax, x1, x2, y, color=BORDER_GREY, lw=1, style="--"):
    ax.plot([x1, x2], [y, y], color=color, lw=lw, linestyle=style, zorder=1)


def vline(ax, x, y1, y2, color=BORDER_GREY, lw=1, style="--"):
    ax.plot([x, x], [y1, y2], color=color, lw=lw, linestyle=style, zorder=1)


def title(ax, text, x, y, size=10, color=TEXT_SECONDARY):
    ax.text(x, y, text, ha="left", va="center", fontsize=size,
            color=color, fontstyle="italic", zorder=5)


# ─────────────────────────────────────────────────────────────────────────────
# 1. Cluster Layout
# ─────────────────────────────────────────────────────────────────────────────
def diagram_cluster_layout():
    W, H = 14, 8
    fig, ax = new_fig(W, H)

    # Proxmox outer frame
    proxmox = FancyBboxPatch(
        (0.4, 1.8), 13.2, 5.9,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor=BOX_DARK, edgecolor=BORDER_ORANGE, linewidth=2, zorder=1,
    )
    ax.add_patch(proxmox)
    ax.text(7, 7.55, "Proxmox Host", ha="center", va="center",
            fontsize=11, color=TEXT_ORANGE, fontweight="bold", zorder=3)

    # Controller
    box(ax, 0.7, 3.8, 2.8, 3.4,
        "k3s-controller-01",
        "172.16.10.1\n8 cores · 16 GB RAM\nvda: 200 GB (OS)\nk3s server\nHelm · ArgoCD",
        fill=BOX_ACCENT, edge=BORDER_BLUE, label_color=TEXT_BLUE,
        sub_color=TEXT_SECONDARY, sub_size=7)

    # Workers
    workers = [
        ("k3s-worker-01", "172.16.10.2", 3.8),
        ("k3s-worker-02", "172.16.10.3", 7.1),
        ("k3s-worker-03", "172.16.10.4", 10.4),
    ]
    for name, ip, xpos in workers:
        box(ax, xpos, 3.8, 2.8, 3.4,
            name,
            f"{ip}\n16 cores · 32 GB RAM\nvda: 200 GB (OS)\nvdb: 512 GB (LVM)\nk3s agent",
            fill=BOX_GREEN, edge=BORDER_GREEN, label_color=TEXT_GREEN,
            sub_color=TEXT_SECONDARY, sub_size=7)

    # Cilium bar across bottom inside Proxmox
    cilium = FancyBboxPatch(
        (0.7, 2.0), 12.8, 1.5,
        boxstyle="round,pad=0,rounding_size=0.2",
        facecolor=BOX_PURPLE, edgecolor=BORDER_PURPLE, linewidth=1.5, zorder=2,
    )
    ax.add_patch(cilium)
    ax.text(7, 2.75, "Cilium CNI  ·  kube-proxy replacement  ·  eBGP  ·  dual-stack IPv4/IPv6  ·  Hubble",
            ha="center", va="center", fontsize=9,
            color=TEXT_PURPLE, fontweight="bold", zorder=3)

    # Vertical connectors from VMs to Cilium bar
    for xpos in [2.1, 5.2, 8.5, 11.8]:
        ax.plot([xpos, xpos], [3.8, 3.5], color=BORDER_GREY, lw=1.2, zorder=3)

    # BGP arrow down
    ax.annotate("", xy=(7, 0.9), xytext=(7, 2.0),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_ORANGE, lw=2), zorder=4)
    ax.text(7.15, 1.45, "eBGP  ASN 65000", ha="left", va="center",
            fontsize=8, color=TEXT_ORANGE, zorder=5)

    # Router box
    box(ax, 5.0, 0.1, 4.0, 0.75,
        "Upstream Router  ·  172.16.10.254  ·  ASN 65000",
        "LB pool: 172.16.1.1/24  ·  fd12:3456:789f::/64",
        fill=BOX_ORANGE, edge=BORDER_ORANGE,
        label_color=TEXT_ORANGE, sub_color=TEXT_SECONDARY,
        label_size=8, sub_size=7)

    fig.savefig("docs/diagrams/01-cluster-layout.png",
                dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close(fig)
    print("  ✓  01-cluster-layout.png")


# ─────────────────────────────────────────────────────────────────────────────
# 2. Ingress / Traffic Flow
# ─────────────────────────────────────────────────────────────────────────────
def diagram_ingress():
    W, H = 14, 9
    fig, ax = new_fig(W, H)

    # Client
    box(ax, 5.5, 8.0, 3.0, 0.7, "Client",
        "DNS: *.apps.wagner.org.za → BGP LB IP",
        fill=BOX_MED, edge=BORDER_GREY,
        label_color=TEXT_PRIMARY, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=7.5)

    ax.annotate("", xy=(7, 7.05), xytext=(7, 8.0),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_BLUE, lw=2), zorder=4)

    # Envoy Gateway
    egw = FancyBboxPatch(
        (1.5, 5.6), 11.0, 1.2,
        boxstyle="round,pad=0,rounding_size=0.25",
        facecolor=BOX_ACCENT, edgecolor=BORDER_BLUE, linewidth=2, zorder=2,
    )
    ax.add_patch(egw)
    ax.text(7, 6.37, "Envoy Gateway  (namespace: envoy-gateway-system)",
            ha="center", va="center", fontsize=10,
            color=TEXT_BLUE, fontweight="bold", zorder=3)
    ax.text(2.8, 6.05, ":80 HTTP  ──►  301 Redirect → HTTPS",
            ha="left", va="center", fontsize=8, color=TEXT_SECONDARY, zorder=3)
    ax.text(2.8, 5.82, ":443 HTTPS  ·  TLS terminated  ·  Secret: wagner-tls / kube-system",
            ha="left", va="center", fontsize=8, color=TEXT_SECONDARY, zorder=3)

    # Arrow from gateway down to routes
    ax.annotate("", xy=(7, 5.1), xytext=(7, 5.6),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_GREY, lw=1.5), zorder=4)
    ax.text(7.1, 5.35, "HTTPRoute (attached from any namespace)",
            ha="left", va="center", fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    # 6 backend boxes
    backends = [
        ("argocd-server:80",         "argocd",     "argocd",    0.5,  BOX_PURPLE, BORDER_PURPLE, TEXT_PURPLE),
        ("hubble-ui:80",             "kube-system","hubble",    2.65, BOX_TEAL,   BORDER_TEAL,   TEXT_TEAL),
        ("argo-workflows-server\n:2746", "argo",  "workflows", 4.8,  BOX_GREEN,  BORDER_GREEN,  TEXT_GREEN),
        ("grafana:80",               "monitoring", "grafana",   7.0,  BOX_ORANGE, BORDER_ORANGE, TEXT_ORANGE),
        ("prometheus:9090",          "monitoring", "prometheus",9.15, BOX_RED,    BORDER_RED,    TEXT_RED),
        ("alertmanager:9093",        "monitoring", "alertmgr",  11.3, BOX_MED,    BORDER_GREY,   TEXT_PRIMARY),
    ]

    # horizontal line from gateway bottom centre outward
    ax.plot([0.5, 13.5], [5.1, 5.1], color=BORDER_GREY, lw=1, linestyle="--", zorder=1)

    for svc, ns, label, xpos, fill, edge, tcolor in backends:
        cx = xpos + 1.0
        # vertical drop
        ax.plot([cx, cx], [5.1, 4.6], color=BORDER_GREY, lw=1.2, zorder=3)
        ax.annotate("", xy=(cx, 3.7), xytext=(cx, 4.6),
                    arrowprops=dict(arrowstyle="-|>", color=edge, lw=1.5), zorder=4)
        box(ax, xpos, 2.4, 2.2, 1.2, svc, f"ns: {ns}",
            fill=fill, edge=edge, label_color=tcolor,
            sub_color=TEXT_SECONDARY, label_size=7.5, sub_size=6.5)

    # hostname labels at top of each arrow
    hostnames = [
        "argocd\n.apps.wagner.org.za",
        "hubble\n.apps.wagner.org.za",
        "workflows\n.apps.wagner.org.za",
        "grafana\n.apps.wagner.org.za",
        "prometheus\n.apps.wagner.org.za",
        "alertmanager\n.apps.wagner.org.za",
    ]
    for i, (hn, (_, _, _, xpos, *_)) in enumerate(zip(hostnames, backends)):
        cx = xpos + 1.0
        ax.text(cx, 1.9, hn, ha="center", va="top",
                fontsize=6, color=TEXT_SECONDARY, zorder=5)

    # Title / legend
    ax.text(7, 0.3, "All routes use HTTPS via *.apps.wagner.org.za  ·  Cilium BGP advertises LoadBalancer IPs",
            ha="center", va="center", fontsize=8, color=TEXT_SECONDARY, fontstyle="italic", zorder=5)

    fig.savefig("docs/diagrams/02-ingress-traffic-flow.png",
                dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close(fig)
    print("  ✓  02-ingress-traffic-flow.png")


# ─────────────────────────────────────────────────────────────────────────────
# 3. GitOps / Sync Wave Ordering
# ─────────────────────────────────────────────────────────────────────────────
def diagram_gitops():
    W, H = 14, 10
    fig, ax = new_fig(W, H)

    # Git repo
    box(ax, 4.0, 8.8, 6.0, 0.9,
        "git.wagner.org.za/homelab/k3s-ansible",
        "gitops/apps/argo-suite/  ·  gitops/networking/",
        fill=BOX_MED, edge=BORDER_GREY,
        label_color=TEXT_PRIMARY, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=7.5)

    ax.annotate("", xy=(7, 7.95), xytext=(7, 8.8),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_GREY, lw=1.5), zorder=4)
    ax.text(7.1, 8.35, "App-of-Apps applied once by Ansible",
            ha="left", va="center", fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    # ArgoCD
    box(ax, 5.5, 7.15, 3.0, 0.7,
        "ArgoCD",
        "",
        fill=BOX_ACCENT, edge=BORDER_BLUE,
        label_color=TEXT_BLUE, label_size=10)

    ax.annotate("", xy=(7, 6.5), xytext=(7, 7.15),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_BLUE, lw=2), zorder=4)

    # Wave frames
    waves = [
        # (y_top, wave_label, wave_color, border_color, apps, app_colors)
        (5.8, "Wave  −1", BOX_RED, BORDER_RED, TEXT_RED,
         [("gateway-api", "CRDs: Gateway · HTTPRoute · GRPCRoute · v1.2.1 experimental")],
         [TEXT_RED]),
        (4.1, "Wave  0", BOX_ACCENT, BORDER_BLUE, TEXT_BLUE,
         [
             ("argocd",        "self-managed  chart 9.4.*  prune=false"),
             ("argo-workflows", "chart 0.47.*  auth-mode: sso"),
             ("argo-rollouts",  "chart 2.40.*  dashboard enabled"),
             ("argo-events",    "chart 2.4.*   JetStream/NATS bus"),
             ("cert-manager",   "DNS-01  enableGatewayAPI=true  3 replicas"),
             ("envoy-gateway",  "GatewayClass: envoy-gateway"),
             ("reflector",      "mirrors Secrets/ConfigMaps across namespaces"),
             ("directpv",       "MinIO DirectPV CSI  non-replicated  /dev/vdb raw"),
             ("longhorn",       "replicated distributed storage  2 replicas  default SC"),
             ("kube-prom-stack","Prometheus 50Gi  Grafana  Alertmanager 5Gi"),
             ("loki",           "SingleBinary  filesystem 20Gi  schema v13/tsdb"),
         ],
         [TEXT_BLUE] * 11),
        (1.6, "Wave  1", BOX_GREEN, BORDER_GREEN, TEXT_GREEN,
         [
             ("k8s-monitoring", "Grafana Alloy: metrics→Prometheus  logs/events→Loki"),
             ("networking",     "Gateway  HTTP→HTTPS redirect  6 HTTPRoutes"),
         ],
         [TEXT_GREEN, TEXT_GREEN]),
    ]

    for y_top, wlabel, wfill, wedge, wtext, apps, acolors in waves:
        h = y_top - (y_top - len(apps) * 0.42 - 0.6)
        # wave frame
        wframe = FancyBboxPatch(
            (0.5, y_top - h), 13.0, h,
            boxstyle="round,pad=0,rounding_size=0.2",
            facecolor=wfill, edgecolor=wedge, linewidth=1.8, alpha=0.25, zorder=1,
        )
        ax.add_patch(wframe)
        ax.text(0.85, y_top - 0.25, wlabel, ha="left", va="center",
                fontsize=10, color=wtext, fontweight="bold", zorder=4)

        for i, ((app, desc), acolor) in enumerate(zip(apps, acolors)):
            y_item = y_top - 0.55 - i * 0.42
            # small box per app
            app_box = FancyBboxPatch(
                (1.8, y_item - 0.15), 11.2, 0.35,
                boxstyle="round,pad=0,rounding_size=0.08",
                facecolor=BOX_DARK, edgecolor=wedge, linewidth=1, alpha=0.9, zorder=2,
            )
            ax.add_patch(app_box)
            ax.text(2.1, y_item + 0.025, app, ha="left", va="center",
                    fontsize=8.5, color=acolor, fontweight="bold", zorder=3)
            ax.text(5.5, y_item + 0.025, desc, ha="left", va="center",
                    fontsize=7.5, color=TEXT_SECONDARY, zorder=3)

        # connector to next wave
        ax.annotate("", xy=(7, y_top - h - 0.05), xytext=(7, y_top - h + 0.12),
                    arrowprops=dict(arrowstyle="-|>", color=BORDER_GREY, lw=1.5), zorder=4)

    fig.savefig("docs/diagrams/03-gitops-sync-waves.png",
                dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close(fig)
    print("  ✓  03-gitops-sync-waves.png")


# ─────────────────────────────────────────────────────────────────────────────
# 4. Storage Architecture
# ─────────────────────────────────────────────────────────────────────────────
def diagram_storage():
    W, H = 16, 10
    fig, ax = new_fig(W, H)

    # Title
    ax.text(8, 9.65, "Storage Architecture — per Worker Node (×3)",
            ha="center", va="center", fontsize=12,
            color=TEXT_PRIMARY, fontweight="bold", zorder=5)

    # Worker node outer frame
    wframe = FancyBboxPatch(
        (0.3, 0.3), 15.4, 9.0,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor=BOX_DARK, edgecolor=BORDER_GREEN, linewidth=2, zorder=1,
    )
    ax.add_patch(wframe)
    ax.text(0.75, 9.1, "Worker Node  (k3s-worker-01 / 02 / 03)", ha="left", va="center",
            fontsize=9, color=TEXT_GREEN, fontweight="bold", zorder=3)

    # ── LEFT COLUMN: vda OS + vdc Longhorn ───────────────────────────────────
    ax.text(3.5, 8.8, "Longhorn v2  —  Replicated Storage", ha="center", va="center",
            fontsize=10, color=TEXT_BLUE, fontweight="bold", zorder=4)

    box(ax, 0.6, 7.5, 5.8, 1.0,
        "/dev/vda  ·  virtio0  ·  200 GB",
        "OS  ·  k3s runtime  ·  container images",
        fill=BOX_MED, edge=BORDER_GREY,
        label_color=TEXT_PRIMARY, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=8)

    box(ax, 0.6, 6.1, 5.8, 1.1,
        "/dev/vdc  ·  virtio2  ·  512 GB",
        "Longhorn data disk  ·  XFS formatted by Ansible\nmounted at /var/lib/longhorn",
        fill=BOX_ACCENT, edge=BORDER_BLUE,
        label_color=TEXT_BLUE, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=7.5)

    # arrow from vdc into Longhorn directory label
    ax.annotate("", xy=(3.5, 5.6), xytext=(3.5, 6.1),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_BLUE, lw=2), zorder=4)
    ax.text(3.65, 5.83, "mkfs.xfs  +  mount", ha="left", va="center",
            fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    box(ax, 0.6, 4.8, 5.8, 0.65,
        "Longhorn Replica Store",
        "/var/lib/longhorn",
        fill=BOX_ACCENT, edge=BORDER_BLUE,
        label_color=TEXT_BLUE, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=8)

    # Replicated PVCs
    lpvcs = [
        ("prometheus-db",   "~50 GB  replicas=2", BORDER_PURPLE, TEXT_PURPLE, BOX_PURPLE),
        ("alertmanager-db", "~5 GB   replicas=2", BORDER_RED,    TEXT_RED,    BOX_RED),
        ("loki-data",       "~20 GB  replicas=2", BORDER_GREEN,  TEXT_GREEN,  BOX_GREEN),
        ("<workload PVCs>", "on demand           ", BORDER_GREY,  TEXT_SECONDARY, BOX_MED),
    ]
    ax.text(0.65, 4.6, "PVCs via StorageClass: longhorn  (default)",
            ha="left", va="center", fontsize=8, color=TEXT_SECONDARY,
            fontstyle="italic", zorder=5)
    for i, (name, size, edge, tcolor, fill) in enumerate(lpvcs):
        yp = 4.1 - i * 0.75
        ax.annotate("", xy=(3.5, yp + 0.35), xytext=(3.5, 4.8),
                    arrowprops=dict(arrowstyle="-|>", color=BORDER_BLUE, lw=1,
                                    connectionstyle="arc3,rad=0"), zorder=3)
        box(ax, 0.6, yp, 5.8, 0.55,
            name, size, fill=fill, edge=edge,
            label_color=tcolor, sub_color=TEXT_SECONDARY,
            label_size=8, sub_size=7.5)

    # Longhorn SC badge
    sc1 = FancyBboxPatch(
        (0.6, 0.45), 5.8, 0.7,
        boxstyle="round,pad=0,rounding_size=0.12",
        facecolor=BOX_ACCENT, edgecolor=BORDER_BLUE, linewidth=1.5, zorder=2,
    )
    ax.add_patch(sc1)
    ax.text(3.5, 0.92, "StorageClass: longhorn  (default)",
            ha="center", va="center", fontsize=8.5,
            color=TEXT_BLUE, fontweight="bold", zorder=3)
    ax.text(3.5, 0.63, "WaitForFirstConsumer  ·  replicas=2  ·  reclaimPolicy=Delete",
            ha="center", va="center", fontsize=7, color=TEXT_SECONDARY, zorder=3)

    # ── DIVIDER ───────────────────────────────────────────────────────────────
    ax.plot([8.0, 8.0], [0.5, 9.0], color=BORDER_GREY, lw=1, linestyle="--", zorder=2)

    # ── RIGHT COLUMN: virtio1 / DirectPV ─────────────────────────────────────
    ax.text(12.0, 8.8, "DirectPV  —  Non-Replicated Storage", ha="center", va="center",
            fontsize=10, color=TEXT_ORANGE, fontweight="bold", zorder=4)

    box(ax, 8.5, 7.5, 6.8, 1.0,
        "/dev/vdb  ·  virtio1  ·  512 GB",
        "Raw block device  ·  unformatted  ·  discard=on  ·  iothread=true",
        fill=BOX_ORANGE, edge=BORDER_ORANGE,
        label_color=TEXT_ORANGE, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=8)

    ax.annotate("", xy=(11.9, 6.6), xytext=(11.9, 7.5),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_ORANGE, lw=2), zorder=4)
    ax.text(12.05, 7.05, "kubectl directpv discover", ha="left", va="center",
            fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    box(ax, 8.5, 5.65, 6.8, 0.85,
        "DirectPV Drive  (claimed)",
        "kubectl directpv init drives.yaml",
        fill=BOX_ORANGE, edge=BORDER_ORANGE,
        label_color=TEXT_ORANGE, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=8)

    # DirectPV PVCs
    dpvcs = [
        ("minio-data",       "high-throughput object store", BORDER_ORANGE, TEXT_ORANGE, BOX_ORANGE),
        ("kafka-data",       "high-throughput event stream", BORDER_TEAL,   TEXT_TEAL,   BOX_TEAL),
        ("<workload PVCs>",  "on demand  non-replicated   ", BORDER_GREY,   TEXT_SECONDARY, BOX_MED),
    ]
    ax.text(8.55, 5.45, "PVCs via StorageClass: directpv-min-io",
            ha="left", va="center", fontsize=8, color=TEXT_SECONDARY,
            fontstyle="italic", zorder=5)
    for i, (name, size, edge, tcolor, fill) in enumerate(dpvcs):
        yp = 4.1 - i * 0.9 + 0.6
        ax.annotate("", xy=(11.9, yp + 0.35), xytext=(11.9, 5.65),
                    arrowprops=dict(arrowstyle="-|>", color=BORDER_ORANGE, lw=1,
                                    connectionstyle="arc3,rad=0"), zorder=3)
        box(ax, 8.5, yp, 6.8, 0.6,
            name, size, fill=fill, edge=edge,
            label_color=tcolor, sub_color=TEXT_SECONDARY,
            label_size=8, sub_size=7.5)

    # DirectPV SC badge
    sc2 = FancyBboxPatch(
        (8.5, 0.45), 6.8, 0.7,
        boxstyle="round,pad=0,rounding_size=0.12",
        facecolor=BOX_ORANGE, edgecolor=BORDER_ORANGE, linewidth=1.5, zorder=2,
    )
    ax.add_patch(sc2)
    ax.text(11.9, 0.92, "StorageClass: directpv-min-io",
            ha="center", va="center", fontsize=8.5,
            color=TEXT_ORANGE, fontweight="bold", zorder=3)
    ax.text(11.9, 0.63, "Non-replicated  ·  topology-aware  ·  reclaimPolicy=Delete",
            ha="center", va="center", fontsize=7, color=TEXT_SECONDARY, zorder=3)

    fig.savefig("docs/diagrams/04-storage-architecture.png",
                dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close(fig)
    print("  ✓  04-storage-architecture.png")


# ─────────────────────────────────────────────────────────────────────────────
# 5. Monitoring Data Flow
# ─────────────────────────────────────────────────────────────────────────────
def diagram_monitoring():
    W, H = 14, 9
    fig, ax = new_fig(W, H)

    # Sources band
    src = FancyBboxPatch(
        (0.4, 7.0), 13.2, 1.7,
        boxstyle="round,pad=0,rounding_size=0.25",
        facecolor=BOX_MED, edgecolor=BORDER_GREY, linewidth=1.5, zorder=1,
    )
    ax.add_patch(src)
    ax.text(7, 8.45, "All Cluster Nodes — metrics, logs, events",
            ha="center", va="center", fontsize=10,
            color=TEXT_PRIMARY, fontweight="bold", zorder=3)
    ax.text(7, 7.95, "node-exporter  ·  kube-state-metrics  ·  kubelet  ·  cAdvisor",
            ha="center", va="center", fontsize=8.5, color=TEXT_SECONDARY, zorder=3)
    ax.text(7, 7.6, "pod stdout/stderr  ·  Kubernetes Events",
            ha="center", va="center", fontsize=8.5, color=TEXT_SECONDARY, zorder=3)
    ax.text(7, 7.2, "Proxmox: k3s-worker-01 / k3s-worker-02 / k3s-worker-03  +  k3s-controller-01",
            ha="center", va="center", fontsize=7.5, color=TEXT_SECONDARY, fontstyle="italic", zorder=3)

    # Two arrows down from sources
    ax.annotate("", xy=(3.5, 6.15), xytext=(4.5, 7.0),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_BLUE, lw=2), zorder=4)
    ax.text(2.8, 6.55, "metrics", ha="center", va="center",
            fontsize=8, color=TEXT_BLUE, zorder=5)

    ax.annotate("", xy=(10.5, 6.15), xytext=(9.5, 7.0),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_GREEN, lw=2), zorder=4)
    ax.text(11.1, 6.55, "logs / events", ha="center", va="center",
            fontsize=8, color=TEXT_GREEN, zorder=5)

    # Alloy metrics
    box(ax, 1.5, 4.9, 4.0, 1.0,
        "Grafana Alloy  (metrics)",
        "k8s-monitoring DaemonSet\ncollects Prometheus-format metrics",
        fill=BOX_ACCENT, edge=BORDER_BLUE,
        label_color=TEXT_BLUE, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=7.5)

    # Alloy logs
    box(ax, 8.5, 4.9, 4.0, 1.0,
        "Grafana Alloy  (logs + events)",
        "k8s-monitoring DaemonSet\ncollects pod logs · cluster events",
        fill=BOX_GREEN, edge=BORDER_GREEN,
        label_color=TEXT_GREEN, sub_color=TEXT_SECONDARY,
        label_size=9, sub_size=7.5)

    # Arrows to stores
    ax.annotate("", xy=(3.5, 3.9), xytext=(3.5, 4.9),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_BLUE, lw=2), zorder=4)
    ax.text(3.6, 4.4, "remote_write", ha="left", va="center",
            fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    ax.annotate("", xy=(10.5, 3.9), xytext=(10.5, 4.9),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_GREEN, lw=2), zorder=4)
    ax.text(10.6, 4.4, "push API", ha="left", va="center",
            fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    # Prometheus
    box(ax, 1.0, 2.6, 5.0, 1.1,
        "Prometheus",
        "50 GB · 30 day retention\nremote_write receiver enabled",
        fill=BOX_ORANGE, edge=BORDER_ORANGE,
        label_color=TEXT_ORANGE, sub_color=TEXT_SECONDARY,
        label_size=10, sub_size=8)

    # Loki
    box(ax, 8.0, 2.6, 5.0, 1.1,
        "Loki",
        "20 GB · SingleBinary\nschema v13 / tsdb",
        fill=BOX_GREEN, edge=BORDER_GREEN,
        label_color=TEXT_GREEN, sub_color=TEXT_SECONDARY,
        label_size=10, sub_size=8)

    # Arrows from both stores to Grafana
    ax.annotate("", xy=(5.5, 1.8), xytext=(3.5, 2.6),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_ORANGE, lw=2,
                                connectionstyle="arc3,rad=-0.2"), zorder=4)
    ax.annotate("", xy=(8.5, 1.8), xytext=(10.5, 2.6),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_GREEN, lw=2,
                                connectionstyle="arc3,rad=0.2"), zorder=4)
    ax.text(4.0, 2.1, "PromQL", ha="center", va="center",
            fontsize=7.5, color=TEXT_SECONDARY, zorder=5)
    ax.text(10.0, 2.1, "LogQL", ha="center", va="center",
            fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    # Grafana
    box(ax, 4.5, 0.55, 5.0, 1.1,
        "Grafana",
        "grafana.apps.wagner.org.za\nLoki datasource pre-wired",
        fill=BOX_ORANGE, edge=BORDER_ORANGE,
        label_color=TEXT_ORANGE, sub_color=TEXT_SECONDARY,
        label_size=10, sub_size=8)

    # Alertmanager side box
    box(ax, 0.4, 0.55, 3.6, 1.1,
        "Alertmanager",
        "5 GB  ·  alert routing\nalerting rules from Prometheus",
        fill=BOX_RED, edge=BORDER_RED,
        label_color=TEXT_RED, sub_color=TEXT_SECONDARY,
        label_size=8.5, sub_size=7.5)
    ax.annotate("", xy=(2.2, 2.6), xytext=(2.2, 1.65),
                arrowprops=dict(arrowstyle="-|>", color=BORDER_RED, lw=1.5), zorder=4)
    ax.text(2.35, 2.1, "alerts", ha="left", va="center",
            fontsize=7.5, color=TEXT_SECONDARY, zorder=5)

    fig.savefig("docs/diagrams/05-monitoring-data-flow.png",
                dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close(fig)
    print("  ✓  05-monitoring-data-flow.png")


# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import os
    os.chdir("/Users/F5281997/Personal/k3s-ansible")
    print("Generating dark-mode architecture diagrams …")
    diagram_cluster_layout()
    diagram_ingress()
    diagram_gitops()
    diagram_storage()
    diagram_monitoring()
    print("Done — files written to docs/diagrams/")
