ARG NEO4J_VERSION
FROM --platform=linux/amd64 neo4j:${NEO4J_VERSION}

# copy my-plugins into the Docker image
COPY my-plugins/ /var/lib/neo4j/plugins

# install the apoc core plugin that is shipped with Neo4j
RUN cp /var/lib/neo4j/labs/apoc-* /var/lib/neo4j/plugins
