require "bundler/setup"
Bundler.require(:default)
Dotenv.load ".env"
require "reline"
require "active_model"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/hash/keys"

pastel = Pastel.new
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

  def filename
    name.gsub(' ', '_').gsub(/[^0-9A-Za-z_]/, '')
  end

  def save
    open("data/#{filename}.json", "w") do |f|
      f.write(to_json)
    end
  end
end

prompt = TTY::Prompt.new
highline = HighLine.new

ROLE_PREFIX_MAPPING = {
  "system" => pastel.yellow(""),
  "user" => pastel.blue("❯"),
  "assistant" => pastel.green("󰚩"),
  "function" => pastel.green("󰊕"),

}

CONTENT_STYLE = Hash.new(pastel.reset.detach)
CONTENT_STYLE["system"] = pastel.yellow.italic.detach

def message_prefix(role)
  "#{ROLE_PREFIX_MAPPING[role.to_s]} "
end

conversation_files = Pathname.pwd.glob("data/*.json")

conversations = conversation_files.map do |file|
  Conversation.new.from_json(file.read)
end


choices = {}

bar = "―"

conversation_selection = nil
begin
  conversation_selection = prompt.select "Choose Conversation:" do |menu|
    conversations.each_with_index do |conversation, i|
      menu.choice name: conversation.name, value: i
    end

    menu.choice name: "Start new...", value: -1
  end
rescue TTY::Reader::InputInterrupt
  exit 0
end

if conversation_selection < 0
  name = prompt.ask "Name of conversation:"
  context = prompt.ask "Initial context:"

  messages = [{role: "system", content: context}]
  conversation = Conversation.new(name: name, messages: messages)
else
  conversation = conversations[conversation_selection]
end
conversation.messages.each {|message| message.symbolize_keys!}

conversation.messages.each do |message|
  puts
  puts "#{message_prefix(message[:role])} #{CONTENT_STYLE[message[:role]].call(message[:content])}"
  puts
  puts bar * 80
end

spinner = TTY::Spinner.new(":spinner Thinking...", format: :arrow_pulse, clear: true)

gather = /\A(done|end|eof|exit)\z/i
loop do
  input = []
  puts
  puts pastel.dim.italic("(type 'end' on its own line when done)")
  user_message = Reline.readmultiline(message_prefix("user"), true) do |multiline_input|
    # Accept the input until `end` is entered
    multiline_input.split.last =~ gather
  end

  case user_message&.downcase
  when nil, gather
    break
  end

  conversation.messages << {role: "user", content: user_message}
  conversation.save

  puts
  puts bar * 80
  puts


  spinner.auto_spin
  response = llm.chat messages: conversation.messages
  spinner.stop
  
  message = {role: "assistant", content: response}
  puts "#{message_prefix("assistant")} #{response}"
  conversation.messages << message
  conversation.save

  puts
  puts bar * 80
end


