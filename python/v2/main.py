from modules.environment.environment_utilities import (
    load_environment_variables,
    verify_environment_variables,
)
from modules.datasources.wikipedia import load_wikipedia_data, process_wikipedia_data
from modules.langchain.langchain import initialize_qa_workflow, execute_qa_workflow
from modules.neo4j.credentials import neo4j_credentials
from modules.neo4j.vector import (
    store_data_in_neo4j,
    initialize_neo4j_vector,
    perform_similarity_search,
)


def load_data_from_wikipedia_and_store_openai_embeddings_in_neo4j_vector(query):
    try:
        print(
            f"\nLoad data from Wikipedia and store OpenAI embeddings in a Neo4j Vector\n\tQuery: {query}\n"
        )

        raw_docs = load_wikipedia_data(query)
        processed_docs = process_wikipedia_data(raw_docs)
        store_data_in_neo4j(processed_docs, neo4j_credentials)

    except Exception as e:
        print(f"\n\tAn unexpected error occurred: {e}")


def query_against_an_existing_neo4j_vector(index_name, query):
    try:
        print(f"\nQuery against an existing Neo4j Vector\n\tQuery: {query}\n")

        # Instantiate Neo4j vector from an existing vector
        neo4j_vector = initialize_neo4j_vector(neo4j_credentials, index_name)

        # Perform the similarity search and display results
        results = perform_similarity_search(neo4j_vector, query)

        # Close the Neo4j connection
        neo4j_vector._driver.close()

        # Do something with the results
        print(results[0].page_content)

    except Exception as e:
        print(f"\n\tAn unexpected error occurred: {e}")


def question_answer_workflow_with_langchain(index_name, query):
    try:
        print(f"\nQuestion/Answer workflow with LangChain\n\tQuery: {query}\n")

        neo4j_vector = initialize_neo4j_vector(neo4j_credentials, index_name)

        # Initialize and execute the QA workflow
        qa_workflow = initialize_qa_workflow(
            neo4j_vector, neo4j_credentials["openai_api_secret_key"]
        )

        qa_results = execute_qa_workflow(
            neo4j_vector, qa_workflow, query, neo4j_credentials["openai_api_secret_key"]
        )
        print(qa_results["answer"])

        # Close the Neo4j connection
        neo4j_vector._driver.close()

    except Exception as e:
        print(f"\n\tAn unexpected error occurred: {e}")


# Main program
try:
    # Load environment variables using the utility
    env_vars = load_environment_variables()
    VECTOR_INDEX_NAME = "vector"

    # Verify the environment variables
    if not verify_environment_variables(env_vars):
        raise ValueError("Some environment variables are missing!")

    # Step 1
    query = "Leonhard Euler"
    load_data_from_wikipedia_and_store_openai_embeddings_in_neo4j_vector(query)

    # Step 2
    # CYPHER - "SHOW INDEXES;" will show we have an index type Vector named "vector"
    query = "Where did Euler grow up?"
    query_against_an_existing_neo4j_vector(VECTOR_INDEX_NAME, query)

    # Step 3
    query = "What is Euler credited for popularizing?"
    question_answer_workflow_with_langchain(VECTOR_INDEX_NAME, query)

except Exception as e:
    print(f"An unexpected error occurred: {e}")
