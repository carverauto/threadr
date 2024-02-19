from .neo4j_adapter import Neo4jAdapter

# Initialize your Neo4jAdapter with connection details
neo4j_adapter = Neo4jAdapter(uri="bolt://localhost:7687", user="neo4j",
                             password="your_password")


def process_cloudevent(data):
    """
    Process the received CloudEvent data.
    """

    # Extract information from the data to form a relationship
    # For demonstration, let's assume data is a simple dictionary
    # and contains 'from_user', 'to_user', and 'relationship_type'
    from_user = data.get('from_user')
    to_user = data.get('to_user')
    relationship_type = data.get('relationship_type')

    if from_user and to_user and relationship_type:
        # Use the Neo4j adapter to add or update the relationship
        try:
            neo4j_adapter.add_or_update_relationship(from_user, to_user,
                                                     relationship_type)
            print(f"Updated relationship between {from_user} and {to_user} "
                  f"as {relationship_type}.")
        except Exception as e:
            print(f"Failed to update Neo4j: {e}")
