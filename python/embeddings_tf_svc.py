import tensorflow as tf
import tensorflow_text as tf_text

# Load a pre-trained word embedding model
text_embedder = tf_text.SentencepieceTokenizer(
    model=tf.keras.utils.get_file(
        f"text_embedding_model.tflite",
        "https://storage.googleapis.com/download.tensorflow.org/models/tflite/text_embedding/1.0/text_embedding_model.tflite",
    )
)

# Sample words 
words = ["cat", "dog", "kitchen", "computer", "sky"]

# Embed the words
embeddings = text_embedder(tf.constant(words))

# Calculate cosine similarity (example)
similarity_matrix = tf.matmul(embeddings, embeddings, transpose_b=True)

# Find the most similar word to "dog"
most_similar_index = tf.argmax(similarity_matrix[1], axis=0).numpy()
most_similar_word = words[most_similar_index]

print(f"The most similar word to 'dog' is: {most_similar_word}")