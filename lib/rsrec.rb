require 'rsrec/version'
module S19
  class SRecordError < RuntimeError
  end

  #Represents a line in the S-Record format
  #
  #http://en.wikipedia.org/wiki/SREC_%28file_format%29
  class SRecord
    attr_reader :binary,:data,:record_type,:byte_count,:address
    def initialize rtype,addr,data
      self.record_type= rtype
      @address = addr
      self.data=data
    end

    def to_s
      "S#{@record_type}#{"%02x"% @byte_count}#{format_address}#{@data}#{crc}".upcase
    end
    #Returns the S-Record CRC 
    def crc
      SRecord.calculate_crc("#{"%02x"% @byte_count}#{format_address}#{@data}")
    end
    #Parses a single line in SREC format and returns an SRecord instance
    def self.parse text_data
      text_data.chomp!
      #duplicate because we're slicing and dicing and throwing stuff away
      line=text_data.dup
      #the (0..0) is for 1.8.7 compatibility, in 1.9 it gives the sliced char back
      if line.slice!(0..0)=='S'
        record_type = line.slice!(0..0).to_i
        #convert everything to hex
        #take out the byte count
        line.slice!(0..1).to_i(16)
        address = calculate_address(record_type,line)
        #take out the crc
        line.slice!(-2..-1)
        data = line
        check_crc(text_data)
        return SRecord.new(record_type,address,data)
      else
        raise SRecordError,"Line without leading S"
      end
    end
    #True if the record is of type 1,2 or 3
    def data_record?
      [1,2,3].include?(@record_type)
    end
    private
    #Set the data.
    #
    #pld is just the payload in hex text format (2nhex digits pro byte)
    def data= pld
      @data=pld
      @binary=SRecord.extract_data(pld)
      #number of bytes in address+data+checksum (checksum is 1 byte)
      @byte_count=format_address.size/2+@binary.size+1
    end
    #Raises SRecordError if supplied with an invalid record type
    def record_type= rtype
      case rtype
      when 0,1,2,3,4,5,6,7,8,9
        @record_type=rtype
      else
        raise SRecordError,"Invalid record type: '#{rtype}'. Should be a number"
      end
    end
    #String representation of the address left padded with 0s
    def format_address 
      case @record_type
        when 0,1,5,9
          return "%04x"% @address
        when 2,8
          return "%06x"% @address
        when 3,7
          return "%08x"% @address
      end
    end
    #Gets 2n chars and converts them to hex
    #
    #n depends on the record type
    def self.calculate_address record_type,line
      case record_type
        when 0,1,5,9
        #2 character pairs
          address=line.slice!(0..3).to_i(16)
        when 2,8
        #3 character pairs
          address=line.slice!(0..5).to_i(16)
        when 3,7
        #4 character pairs
          address=line.slice!(0..7).to_i(16)
      else
          raise SRecordError,"Cannot calculate address. Unknown record type #{@record_type}"
      end
      return address
    end
    #From an SREC text line calculate the CRC and check it against the embedded CRC
    def self.check_crc raw_data
      line = raw_data.dup
      #chop of the S, the record type and the crc
      line.slice!(0..1)
      crc=line.slice!(-2..-1)
      calculated_crc=calculate_crc(line)
      if calculated_crc.upcase == crc.upcase
        return crc
      else
        raise SRecordError, "CRC failure: #{calculated_crc} instead of #{crc}"
      end
    end
    
    def self.calculate_crc line_data
      data=extract_data(line_data)
      data_sum=data.inject(0){|sum,item| sum + item}
      #least significant byte is
      lsb=data_sum & 0xFF
      #1's complement of lsb and in hex string format
      ("%02x"% (lsb^0xFF)).upcase
    end
    #Converts 2n hex characters in n bytes
    def self.extract_data data_string
      line=data_string.dup
      binary=[]
      while !line.empty?
        data_chars = line.slice!(0..1)
        binary<<data_chars.to_i(16)
      end
      return binary
    end
  end

  class MotFile
    attr_reader :records
    def initialize records=[]
      @records=records
    end
    def to_s
      @records.each_with_object(""){|record,msg| msg<<"#{record}\n"}
    end
    #Just the data records
    def data_records
      @records.select{|rec| rec.data_record?}.compact
    end
    #The total size of the image in bytes
    def image_size
      data_records.last.address+data_records.last.binary.size-data_records.first.address
    end
    #Parses a .mot file in memory, returns MotFile
    def self.from_file filename
      records=File.readlines(filename).map{|line| SRecord.parse(line)}
      MotFile.new(records)
    end
  end
end
