from flask import Flask, request, jsonify
from llama_cpp import Llama
import os

app = Flask(__name__)

# Initialize your Llama model
model_path = "/Users/mfreeman/Downloads/mistral-7b-instruct-v0.1.Q6_K.gguf"  # Adjust path as necessary
llm = Llama(model_path=model_path, n_ctx=8192, n_batch=512, n_threads=7, n_gpu_layers=2, verbose=True, seed=42)

@app.route('/generate', methods=['POST'])
def generate():
    # Extract instruction from request
    data = request.json
    system = data.get('system', '')
    user = data.get('user', '')

    # Prepare message
    message = f"<s>[INST] {system} [/INST]</s>{user}"

    # Generate output with Llama model
    try:
        output = llm(message, echo=True, stream=False, max_tokens=4096)
        usage_info = output['usage']
        generated_text = output['choices'][0]['text'].replace(message, '')

        # Respond with generated text and usage info
        return jsonify({"generated_text": generated_text, "usage_info": usage_info})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, port=5001)
