require "bundler/setup"
Bundler.require(:default)
Dotenv.load ".env"
require "reline"
require "active_model"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/hash/keys"
require "facets/string/indent"

pastel = Pastel.new
llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
prompt = TTY::Prompt.new

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

  def self.all
    Pathname.pwd.glob("data/*.json").map do |file|
      new.from_json(file.read)
    end
  end
end

class ChatUI
  def self.pastel
    @pastel ||= Pastel.new
  end
  
  def pastel
    self.class.pastel
  end

  def prompt
    @prompt ||= TTY::Prompt.new
  end

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

  BAR = "─"
  def separator(width = 80)
    BAR * width
  end

  def select_conversation(conversations)
    prompt.select "Choose Conversation:" do |menu|
      conversations.each do |conversation|
        menu.choice name: conversation.name, value: conversation
      end

      menu.choice name: "Start new...", value: nil
    end
  end

  def create_conversation
    name = Reline.readline("Name of conversation: ")
    context = Reline.readline("Initial context: ")

    messages = [{role: "system", content: context}]
    Conversation.new(name: name, messages: messages)
  end

  def display(conversation)
    conversation.messages.each do |message|
      puts
      puts "#{message_prefix(message[:role])} #{CONTENT_STYLE[message[:role]].call(message[:content])}"
      puts
      puts separator
    end
  end

  DONE = %w(done end eof exit).freeze

  def prompt_for_message
    puts pastel.dim.italic("(multiline input; type 'end' on its own line when done. or exit to exit)")
    user_message = Reline.readmultiline(message_prefix("user"), true) do |multiline_input|
      # Accept the input until `end` is entered
      last = multiline_input.split.last
      DONE.include?(last) || last == "clear"
    end

    return :noop unless user_message

    lines = user_message.split("\n")
    if lines.size > 1 && DONE.include?(lines.last)
      # remove the "done" from the message
      user_message = lines[0..-2].join("\n")
    end

    return :clear if user_message == "clear"

    return :exit if DONE.include?(user_message.downcase)

    user_message
  end

  def wait
    spinner.auto_spin
    result = yield
    spinner.stop
    result
  end

  def spinner
    @spinner ||= TTY::Spinner.new(":spinner Thinking...", format: :arrow_pulse, clear: true)
  end

  CLEAR = "\e[H\e[2J"
  def clear
    puts CLEAR
  end

end

chat = ChatUI.new

conversations = Conversation.all 
conversation = begin 
                 chat.select_conversation(conversations)
               rescue TTY::Reader::InputInterrupt
                 exit 0
               end

# start new conversation if none selected
conversation ||= chat.create_conversation

# serialized as JSON, which doesn't preserve symbol keys
conversation.messages.each(&:symbolize_keys!)

# display existing conversation
chat.display(conversation)

begin
  loop do
    user_message = chat.prompt_for_message

    case user_message
    when :noop
      next
    when :clear
      chat.clear
      next
    when :exit
      break
    end

    conversation.messages << {role: "user", content: user_message}
    conversation.save

    puts
    puts chat.separator
    puts

    response = chat.wait do
      llm.chat messages: conversation.messages
    end
    
    message = {role: "assistant", content: response}
    conversation.messages << message
    conversation.save
    puts "#{chat.message_prefix("assistant")} #{response}"

    puts
    puts chat.separator
  end
rescue Interrupt
  exit 0
end


