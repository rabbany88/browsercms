module Cms
  module Upgrades

    module V3_5_0
      def upgrade_to_3_5_0
        gsub_file "config/environments/production.rb", /config.action_controller.page_cache_directory.+$/, ""
      end

      module FileStorageUpdates

        # Old paths are:
        #       uploads/:year/:month/:day/:fingerprint
        # i.e.  uploads/2012/04/27/fb598......
        #
        # New paths use paperclip's :id_partition which creates paths like:
        #       uploads/000/000/001/:fingerprint
        # where it splits the id into multiple directories
        #
        def new_file_location(attachment)
          new_id_dir = "#{Paperclip::Interpolations.id_partition(AttachmentWrapper.new(attachment), nil)}/original"
          return "#{new_id_dir}/#{attachment.data_fingerprint}", new_id_dir
        end

        # Move the attachment files from the old file path path to new one. Updates the Attachment record to match.
        def move_attachments_to_new_location
          migrate_attachments_file_location(Cms::Attachment)
          migrate_attachments_file_location(Cms::Attachment::Version)
        end

        private

        # Multiple version of attachments may point to the same file, so we need to test
        # a file exists before moving. Failure to move isn't necessary an error, since it may have been moved in
        # an earlier version
        def migrate_attachments_file_location(model_class)
          model_class.unscoped.where("attachable_type is NOT NULL").each do |attachment|
            old_location = File.join(Cms::Attachment.configuration.attachments_root, attachment.file_location)
            new_file_location, new_dir = new_file_location(attachment)
            new_location = File.join(Cms::Attachment.configuration.attachments_root, new_file_location)
            new_dir_path = File.join(Cms::Attachment.configuration.attachments_root, new_dir)

            FileUtils.mkdir_p(new_dir_path, :verbose => false)
            if File.exists?(old_location)
              FileUtils.mv(old_location, new_location, :verbose => true)
            else
              puts "'#{old_location}' does not exist, and may have been moved already. Skipping move."
            end

            new_fingerprint = attachment.file_location.split("/").last
            model_class.unscoped.update_all({:data_fingerprint => new_fingerprint}, :id => attachment.id)
          end
        end

        # Allows us to use the Paperclip interpolations logic directly
        class AttachmentWrapper
          def initialize(attachment)
            @attachment = attachment
          end

          def instance
            @attachment
          end
        end
      end
    end
  end
end