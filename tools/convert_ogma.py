import _compat  # noqa
import sys, torch, numpy as np
from transformers import AutoConfig, AutoTokenizer
from transformers.dynamic_module_utils import get_class_from_dynamic_module
from safetensors.torch import load_file
import coremltools as ct
P = sys.argv[1]; name = P.split("/")[-1]
cfg = AutoConfig.from_pretrained(P, trust_remote_code=True)
tok = AutoTokenizer.from_pretrained(P, trust_remote_code=True)
model = get_class_from_dynamic_module("ogma_model.OgmaModel", P)(cfg).eval()
model.load_state_dict(load_file(f"{P}/model.safetensors"), strict=False)
class Wrap(torch.nn.Module):
    def __init__(s, m): super().__init__(); s.m=m
    def forward(s, input_ids, attention_mask):
        return torch.nn.functional.normalize(s.m(input_ids=input_ids, attention_mask=attention_mask), p=2, dim=1)
wrap = Wrap(model).eval()
enc = tok(["[DOC] the quick brown fox"], return_tensors="pt", padding=True)
ids, mask = enc["input_ids"].int(), enc.get("attention_mask", torch.ones_like(enc["input_ids"])).int()
with torch.no_grad(): ref = wrap(ids, mask).numpy()
traced = torch.jit.trace(wrap, (ids, mask), strict=False)
sl = ct.RangeDim(lower_bound=1, upper_bound=1024, default=16)
ml = ct.convert(traced,
    inputs=[ct.TensorType(name="input_ids", shape=(1, sl), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, sl), dtype=np.int32)],
    minimum_deployment_target=ct.target.macOS13, compute_units=ct.ComputeUnit.ALL)
ml.save(f"models/{name}.mlpackage")
pred = ml.predict({"input_ids": ids.numpy().astype(np.int32), "attention_mask": mask.numpy().astype(np.int32)})
key = list(pred.keys())[0]
cl = np.asarray(pred[key]).reshape(-1)
cos = float(np.dot(ref.reshape(-1), cl) / (np.linalg.norm(ref) * np.linalg.norm(cl)))
print(f"{name}: dim={cl.shape[0]} parity_cosine={cos:.5f} out_key={key}")
