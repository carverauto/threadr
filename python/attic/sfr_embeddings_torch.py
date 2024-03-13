import torch
from transformers import AutoTokenizer, AutoModel
import time

def create_embeddings(texts):
    # Tokenize texts
    batch_dict = tokenizer(texts, return_tensors="pt", padding=True, truncation=True)
    # Compute model outputs
    with torch.no_grad():  # Disable gradient calculation for faster computation
        outputs = model(**batch_dict)
    # Extract embeddings (for simplicity, use the last hidden state directly)
    embeddings = outputs.last_hidden_state.mean(dim=1)
    return embeddings

# Load model and tokenizer
tokenizer = AutoTokenizer.from_pretrained('Salesforce/SFR-Embedding-Mistral')
model = AutoModel.from_pretrained('Salesforce/SFR-Embedding-Mistral')

# Example chat logs
chat_logs = [
    "How to bake a chocolate cake?",
    "Symptoms of the flu",
    # Add more chat logs as needed
]

# Run the embedding creation in a loop 5 times
num_iterations = 5
times = []  # To store time taken for each iteration

for i in range(num_iterations):
    start_time = time.time()
    embeddings = create_embeddings(chat_logs)
    end_time = time.time()
    iteration_time = end_time - start_time
    times.append(iteration_time)
    print(f"Iteration {i+1}: Time taken = {iteration_time:.2f} seconds")

# Print the shape of the embeddings to verify
print("Embeddings shape:", embeddings.shape)

# Optional: Compute and print average time excluding the first iteration
if len(times) > 1:
    avg_time_excluding_first = sum(times[1:]) / (num_iterations - 1)
    print(f"Average time excluding the first iteration: {avg_time_excluding_first:.2f} seconds")
