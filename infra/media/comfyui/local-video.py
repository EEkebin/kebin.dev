"""Install V100-sized workflows using ComfyUI's bundled LTX templates and native nodes."""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
templates = next(root.glob(".venv/lib/python*/site-packages/comfyui_workflow_templates_json/templates"))
out = root / "user/default/workflows/Local video"
out.mkdir(parents=True, exist_ok=True)
for mode in ("text", "image"):
    flow = json.loads((templates / f"ltxv_{mode}_to_video.json").read_text())
    for node in flow["nodes"]:
        kind = node["type"]
        widgets = node.get("widgets_values", [])
        if kind in ("LTXVImgToVideo", "EmptyLTXVLatentVideo"):
            widgets[:3] = [512, 320, 49]
        elif kind == "LoadImage":
            widgets[0] = "ltx-starter.png"
        elif kind in ("LTXVConditioning", "CreateVideo"):
            widgets[0] = 24
    (out / f"LTX {mode} to video.json").write_text(json.dumps(flow, indent=2))

# ComfyUI imports API-format workflows and lays out their linked nodes.
def node(kind, **inputs):
    return {"class_type": kind, "inputs": inputs}

graph = {
    "1": node("CheckpointLoaderSimple", ckpt_name="ltx-video-2b-v0.9.5.safetensors"),
    "2": node("CLIPLoader", clip_name="t5xxl_fp16.safetensors", type="ltxv", device="default"),
    "3": node("CLIPTextEncode", clip=["2", 0], text="A cinematic scene at dusk, warm amber lighting, gentle camera movement and realistic detail."),
    "4": node("CLIPTextEncode", clip=["2", 0], text="distortion, blur, artifacts"),
    "5": node("LoadVideo", file="ltx-starter.mp4"),
    "6": node("GetVideoComponents", video=["5", 0]),
    "7": node("ImageFromBatch", image=["6", 0], batch_index=0, length=49),
    "8": node("ImageScale", image=["7", 0], upscale_method="area", width=512, height=320, crop="center"),
    "9": node("VAEEncode", pixels=["8", 0], vae=["1", 2]),
    "10": node("LTXVConditioning", positive=["3", 0], negative=["4", 0], frame_rate=["6", 2]),
    "11": node("KSamplerSelect", sampler_name="euler"),
    "12": node("LTXVScheduler", latent=["9", 0], steps=30, max_shift=2.05, base_shift=0.95, stretch=True, terminal=0.1),
    "13": node("SplitSigmas", sigmas=["12", 0], step=15),
    "14": node("SamplerCustom", model=["1", 0], add_noise=True, noise_seed=48271, cfg=3.0, positive=["10", 0], negative=["10", 1], sampler=["11", 0], sigmas=["13", 1], latent_image=["9", 0]),
    "15": node("VAEDecode", samples=["14", 0], vae=["1", 2]),
    "16": node("CreateVideo", images=["15", 0], fps=["6", 2]),
    "17": node("SaveVideo", video=["16", 0], filename_prefix="video/LTX-edit", format="auto", **{"format.codec": "auto"}),
}
(out / "LTX video to video.json").write_text(json.dumps(graph, indent=2))
