# frozen_string_literal: true

require "rake/tasklib"
require "breadkit/lint"

module Breadkit
  class RakeTask < Rake::TaskLib
    attr_accessor :files, :options

    def initialize(name = :breadkit)
      super()
      @files = []
      @options = []
      yield self if block_given?
      desc "Lint Breadkit circuits"
      task name do
        status = Breadkit::Lint::CLI.new.run(Array(options) + Array(files))
        raise Breadkit::Lint::Error, "bklint failed with status #{status}" unless status.zero?
      end
    end
  end
end
