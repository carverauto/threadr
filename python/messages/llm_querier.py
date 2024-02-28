from langchain.chat_models import ChatOllama
from langchain.prompts import PromptTemplate
from langchain.chains import LLMChain


chat_llm = ChatOllama(
    model="llama2:chat",
    base_url="http://192.168.1.80:11434"
)

prompt = PromptTemplate(
    template="""You are a surfer dude, having a conversation about the surf conditions on the beach.
Respond using surfer slang.

Question: {question}
""",
    input_variables=["question"],
)

chat_chain = LLMChain(
    llm=chat_llm,
    prompt=prompt,
)

response = chat_chain.invoke({"question": "What is the weather like?"})

print(response)