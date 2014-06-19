%global gemname hammer_cli_import
%global confdir hammer
%if 0%{?rhel}
%global gem_dir /usr/lib/ruby/gems/1.8
%endif

%global geminstdir %{gem_dir}/gems/%{gemname}-%{version}

Name:       rubygem-%{gemname}
Version:    0.6.1
Release:    1%{?dist}
Summary:    Sat5-import command plugin for the Hammer CLI

Group:      Development/Languages
License:    GPLv3
URL:        https://github.com/Katello/hammer-cli-import
Source0:    %{gemname}-%{version}.gem
Source1:    import.yml
Source2:    role_map.yml

%if 0%{?rhel} > 6 || 0%{?fedora} > 18
Requires: ruby(release)
%else
Requires: ruby(abi)
%endif
Requires: ruby(rubygems)
Requires: rubygem(hammer_cli)
BuildRequires: ruby(rubygems)
%if 0%{?fedora}
BuildRequires: rubygems-devel
%endif
BuildRequires: ruby
BuildArch: noarch
Provides: rubygem(%{gemname}) = %{version}

%description
Sat5-import plugin for the Hammer CLI

%package doc
Summary: Documentation for %{name}
Group: Documentation
Requires: %{name} = %{version}-%{release}
BuildArch: noarch

%description doc
Documentation for %{name}

%prep
%setup -q -c -T
mkdir -p .%{gem_dir}
gem install --local --install-dir .%{gem_dir} \
            --force %{SOURCE0}

%install
mkdir -p %{buildroot}%{_sysconfdir}/%{confdir}/cli.modules.d
install -m 755 %{SOURCE1} %{buildroot}%{_sysconfdir}/%{confdir}/cli.modules.d/import.yml
install -m 644 %{SOURCE2} %{buildroot}%{_sysconfdir}/%{confdir}/cli.modules.d/role_map.yml
mkdir -p %{buildroot}%{gem_dir}
cp -pa .%{gem_dir}/* \
        %{buildroot}%{gem_dir}/

%files
%dir %{geminstdir}
%{geminstdir}/
%config(noreplace) %{_sysconfdir}/%{confdir}/cli.modules.d/import.yml
%config(noreplace) %{_sysconfdir}/%{confdir}/cli.modules.d/role_map.yml
%exclude %{gem_dir}/cache/%{gemname}-%{version}.gem
%{gem_dir}/specifications/%{gemname}-%{version}.gemspec

%files doc
%doc %{gem_dir}/doc/%{gemname}-%{version}

%changelog
* Thu Jun 19 2014 Grant Gainey 0.6.1-1
- * Look for the default repository-map where the gem puts it * Clarify the
  output when we decide to enable a repo (ggainey@redhat.com)
- let git ignore .swp files (tlestach@redhat.com)

* Thu Jun 19 2014 Tomas Lestach <tlestach@redhat.com> 0.6.0-1
- initial hammer-cli-import tag


