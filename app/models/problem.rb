# Represents a single Problem. The problem may have been
# reported as various Errs, but the user has grouped the
# Errs together as belonging to the same problem.

class Problem
  include Mongoid::Document
  include Mongoid::Timestamps

  field :last_notice_at, :type => DateTime
  field :last_deploy_at, :type => Time
  field :resolved, :type => Boolean, :default => false
  field :issue_link, :type => String

  # Cached fields
  field :app_name, :type => String
  field :notices_count, :type => Integer, :default => 0
  field :message
  field :environment
  field :klass
  field :where
  field :user_agents, :type => Array, :default => []
  field :messages, :type => Array, :default => []
  field :hosts, :type => Array, :default => []

  index :app_id
  index :app_name
  index :message
  index :last_notice_at
  index :last_deploy_at
  index :notices_count

  belongs_to :app
  has_many :errs, :inverse_of => :problem, :dependent => :destroy
  has_many :comments, :inverse_of => :err, :dependent => :destroy

  before_create :cache_app_attributes

  scope :resolved, where(:resolved => true)
  scope :unresolved, where(:resolved => false)
  scope :ordered, order_by(:last_notice_at.desc)
  scope :for_apps, lambda {|apps| where(:app_id.in => apps.all.map(&:id))}


  def self.in_env(env)
    env.present? ? where(:environment => env) : scoped
  end

  def notices
    Notice.for_errs(errs).ordered
  end

  def resolve!
    self.update_attributes!(:resolved => true)
  end

  def unresolve!
    self.update_attributes!(:resolved => false)
  end

  def unresolved?
    !resolved?
  end


  def self.merge!(*problems)
    problems = problems.flatten.uniq
    merged_problem = problems.shift
    problems.each do |problem|
      merged_problem.errs.concat Err.where(:problem_id => problem.id)
      problem.errs(true) # reload problem.errs (should be empty) before problem.destroy
      problem.destroy
    end
    merged_problem.reset_cached_attributes
    merged_problem
  end

  def merged?
    errs.length > 1
  end

  def unmerge!
    problem_errs = errs.to_a
    problem_errs.shift
    [self] + problem_errs.map(&:id).map do |err_id|
      err = Err.find(err_id)
      app.problems.create.tap do |new_problem|
        err.update_attribute(:problem_id, new_problem.id)
        new_problem.reset_cached_attributes
      end
    end
  end


  def self.ordered_by(sort, order)
    case sort
    when "app";            order_by(["app_name", order])
    when "message";        order_by(["message", order])
    when "last_notice_at"; order_by(["last_notice_at", order])
    when "last_deploy_at"; order_by(["last_deploy_at", order])
    when "count";          order_by(["notices_count", order])
    else raise("\"#{sort}\" is not a recognized sort")
    end
  end


  def reset_cached_attributes
    update_attribute(:notices_count, notices.count)
    cache_app_attributes
    cache_notice_attributes
  end

  def cache_app_attributes
    if app
      self.app_name = app.name
      self.last_deploy_at = if (last_deploy = app.deploys.where(:environment => self.environment).last)
        last_deploy.created_at
      end
      self.save if persisted?
    end
  end

  def cache_notice_attributes(notice=nil)
    notice ||= notices.first
    attrs = {:last_notice_at => notices.max(:created_at)}
    attrs.merge!(
      :message => notice.message,
      :environment => notice.environment_name,
      :klass => notice.klass,
      :where => notice.where,
      :messages => messages.push(notice.message),
      :hosts => hosts.push(notice.host),
      :user_agents => user_agents.push(notice.user_agent_string)
      ) if notice
    update_attributes!(attrs)
  end

  def remove_cached_notice_attribures(notice)
    messages.delete_at(messages.index(notice.message))
    hosts.delete_at(hosts.index(notice.host))
    user_agents.delete_at(user_agents.index(notice.user_agent_string))
    save!
  end

end

