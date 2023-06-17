require "bundler/setup"
Bundler.require(:default)
Dotenv.load ".env"
require "active_model"

llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])

class Conversation
  include ActiveModel::API
  include ActiveModel::Serialization
  include ActiveModel::Serializers::JSON

  attr_accessor :name, :messages


  def attributes=(hash)
    hash.each do |key, value|
      send("#{key}=", value)
    end
  end

  def attributes
    {
      name: name,
      messages: messages
    }
  end
end



messages = [
  { role: "system", content: "You are a helpful assistant to help roleplaying game masters and players." },
  { role: "user", content: "I want to run a campaign. It will be using Starfinder. How do I get started planning it?"}
]

conversation = Conversation.new(name: "Starting a Starfinder Game", messages: messages)
binding.pry

# response = llm.chat messages: messages

# messages << {role: "user", content: response}
