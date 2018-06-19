# encoding: utf-8

module FC
  class DbBase
    attr_accessor :id, :database_fields, :additional_fields
    
    class << self
      attr_accessor :table_name, :table_fields
    end
    
    def initialize(params = {})
      self.class.table_fields.each {|key| self.send("#{key}=", params[key] || params[key.to_sym]) }
      @id = (params["id"] || params[:id]).to_i if params["id"] || params[:id]
      @database_fields = params[:database_fields] || {}
      @additional_fields = params[:additional_fields] || {}
    end
    
    def self.table_name
      FC::DB.connect! unless FC::DB.options
      "#{FC::DB.prefix}#{@table_name}"
    end
        
    # define table name and fields
    def self.set_table(name, fields)
      @table_name = name
      self.table_fields = fields.split(',').map{|e| e.gsub(' ','')}
      self.table_fields.each{|e| attr_accessor e.to_sym}
    end
    
    # make instance on fields hash
    def self.create_from_fiels(data)
      # use only defined in set_table fields
      #database_fields = data.select{|key, val| self.table_fields.include?(key.to_s)}
      additional_fields = {}
      database_fields = {}
      data.each do |key, val| 
        if self.table_fields.include?(key.to_s)
          database_fields[key] = val
        elsif key != 'id'
          additional_fields[key.to_sym] = val
        end
      end
      self.new(database_fields.merge({:id => data["id"].to_s, :database_fields => database_fields, :additional_fields => additional_fields}))
    end
    
    # get element by id
    def self.find(id)
      r = FC::DB.query("SELECT * FROM #{self.table_name} WHERE id=#{id.to_i}")
      raise "Record not found (#{self.table_name}.id=#{id})" if r.count == 0
      self.create_from_fiels(r.first)
    end
    
    # get elements array by sql condition (possibles '?' placeholders)
    def self.where(cond = "1", *params)
      i = -1
      sql = "SELECT * FROM #{self.table_name} WHERE #{cond.gsub('?'){i+=1; "'#{Mysql2::Client.escape(params[i].to_s)}'"}}"
      r = FC::DB.query(sql)
      r.map{|data| self.create_from_fiels(data)}
    end
    
    # save changed fields
    def save
      sql = @id.to_i != 0 ? "UPDATE #{self.class.table_name} SET " : "INSERT IGNORE INTO #{self.class.table_name} SET "
      fields = []
      self.class.table_fields.each do |key|
        db_val = @database_fields[key]
        val = self.send(key)
        val = 1 if val == true
        val = 0 if val == false
        if val.to_s != db_val.to_s || val.nil? && !db_val.nil? || !val.nil? && db_val.nil?
          fields << "#{key}=#{val ? (val.class == String ? "'#{FC::DB.connect.escape(val)}'" : val.to_i) : 'NULL'}"
        end
      end
      @additional_fields.each do |key, val|
        val = 1 if val == true
        val = 0 if val == false
        fields << "#{key}=#{val ? (val.class == String ? "'#{FC::DB.connect.escape(val)}'" : val.to_i) : 'NULL'}"
      end
      if fields.length > 0
        sql << fields.join(',')
        sql << " WHERE id=#{@id.to_i}" if @id
        FC::DB.query(sql)
        @id = FC::DB.connect.last_id unless @id
        self.class.table_fields.each do |key|
          @database_fields[key] = self.send(key)
        end
      end
    end
    
    # reload object from DB
    def reload
      raise "Can't reload object without id" if !@id || @id.to_i == 0
      new_obj = self.class.find(@id)
      self.database_fields = new_obj.database_fields
      self.class.table_fields.each {|key| self.send("#{key}=", new_obj.send(key)) }
    end

    # delete object from DB
    def delete
      FC::DB.query("DELETE FROM #{self.class.table_name} WHERE id=#{@id.to_i}") if @id
    end
    
    def self.apply!(data: {}, key_field: :name, update_only: false)
      return nil unless data[key_field]
      obj_instance = where("#{key_field} = ?", data[key_field]).first
      return "#{name} \"#{data[key_field]}\" not found" if obj_instance.nil? && update_only
      obj_instance ||= new
      obj_instance.load(data: data)
      obj_instance.save
      obj_instance
    end

    def load(data: {})
      raise 'This method must be overrided'
    end

    def dump(exclude = [])
      obj_dump = {}
      self.class.table_fields.each do |field|
        sym_field = field.to_sym
        next if exclude.include?(sym_field)
        obj_dump[sym_field] = database_fields[field]
      end
      obj_dump
    end
  end
end
