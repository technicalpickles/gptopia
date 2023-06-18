require "bundler/setup"
Bundler.require(:default)
Dotenv.load ".env"
require "active_model"
require "active_support/core_ext/string/inflections"

llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])

class ChatModel
  include ActiveModel::API
  include ActiveModel::Conversion
  include ActiveModel::Serialization
  include ActiveModel::Serializers::JSON
  include ActiveModel::Model
  include ActiveModel::Validations

  def attributes=(hash)
    hash.each do |key, value|
      send("#{key}=", value)
    end
  end

  def attributes
    raise NotImplementedError
  end
end

class Role
  SYSTEM = :system
  USER = :user
  ASSISTANT = :assistant
  FUNCTION = :function

  VALID_SYMBOLS = [SYSTEM, USER, ASSISTANT, FUNCTION].freeze
  VALID_STRINGS = VALID_SYMBOLS.map(&:to_s).freeze
  VALID = (VALID_SYMBOLS + VALID_STRINGS).freeze
end

class Message < ChatModel
  attr_accessor :role, :content

  validates_inclusion_of :role, in: Role::VALID
  validates :content, presence: true

  def attributes
    {
      role: role,
      content: content
    }
  end
end

class Conversation < ChatModel
  attr_accessor :name, :messages

  validates :name, presence: true

  def attributes
    {
      name: name,
      messages: messages
    }
  end
end


prompt = TTY::Prompt.new

name = prompt.ask "Name of conversation:"
context = prompt.ask "Initial context:"

messages = [Message.new(role: "system", content: context)]
conversation = Conversation.new(name: name, messages: messages)

loop do
  user_message = prompt.ask(">")
  if user_message == "done"
    break
  end
  conversation.messages << Message.new(role: "user", content: user_message)
end

binding.pry

# response = llm.chat messages: messages

# messages << {role: "user", content: response}
