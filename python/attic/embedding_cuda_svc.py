from flask import Flask, request, jsonify
from langchain.embeddings import HuggingFaceBgeEmbeddings

app = Flask(__name__)

# Load the model
model_name = "BAAI/bge-large-en-v1.5"
model_kwargs = {'device': 'cuda'}
encode_kwargs = {'normalize_embeddings': True}
model = HuggingFaceBgeEmbeddings(
    model_name=model_name,
    model_kwargs=model_kwargs,
    encode_kwargs=encode_kwargs,
)

@app.route('/embeddings', methods=['POST'])
def generate_embeddings():
    # Get the sentence from the request
    sentence = request.json['sentence']

    # Generate embeddings
    embeddings = model.encode([sentence])

    # Return the embeddings as a JSON response
    return jsonify({'embeddings': embeddings.tolist()})

if __name__ == '__main__':
    app.run(debug=True)
