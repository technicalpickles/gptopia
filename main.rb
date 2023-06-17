require "bundler/setup"
require "langchain"
require "pry"
require "dotenv"

Dotenv.load ".env"
binding.pry

llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])


messages = [
  { role: "system", content: "You are a helpful assistant to help roleplaying game masters and players." },
  { role: "user", content: "I want to run a campaign. It will be using Starfinder. How do I get started planning it?"}
]


response = llm.chat messages: messages

messages << {role: "user", content: response}
puts response
binding.pry
