from flask import Flask, request, jsonify
import tiktoken

app = Flask(__name__)

# Get the encoding for the model you're interested in
enc = tiktoken.encoding_for_model("gpt-4")

@app.route('/token-count', methods=['POST'])
def token_count():
    # Extract the text from the incoming request
    data = request.json
    text = data.get('text', '')

    # Use the encoder to count tokens
    tokens = enc.encode(text)
    token_count = len(tokens)

    # Return the token count in the response
    return jsonify({"text": text, "token_count": token_count})

if __name__ == '__main__':
    app.run(debug=True, port=5002)
