require 'katello_test_helper'

module Katello
  class ContentFacetBase < ActiveSupport::TestCase
    let(:library) { katello_environments(:library) }
    let(:dev) { katello_environments(:dev) }
    let(:view)  { katello_content_views(:library_dev_view) }
    let(:environment) { katello_environments(:library) }
    let(:empty_host) { ::Host::Managed.create!(:name => 'foobar', :managed => false) }
    let(:host) do
      FactoryGirl.create(:host, :with_content, :content_view => view,
                                     :lifecycle_environment => library)
    end
    let(:content_facet) { host.content_facet }
  end

  class ContentFacetTest < ContentFacetBase
    def test_create
      empty_host.content_facet = Katello::Host::ContentFacet.create!(:content_view_id => view.id, :lifecycle_environment_id => library.id, :host => empty_host)
    end

    def test_content_view_version
      assert_equal view.version(library), host.content_facet.content_view_version
    end

    def test_katello_agent_installed?
      refute host.content_facet.katello_agent_installed?

      host.installed_packages << Katello::InstalledPackage.create!(:name => 'katello-agent', 'nvra' => 'katello-agent-1.0.x86_64')

      assert host.reload.content_facet.katello_agent_installed?
    end

    def test_in_content_view_version_environments
      first_cvve = {:content_view_version => content_facet.content_view.version(content_facet.lifecycle_environment),
                    :environments => [content_facet.lifecycle_environment]}
      second_cvve = {:content_view_version => view.version(library), :environments => [dev]} #dummy set

      facets = Host::ContentFacet.in_content_view_version_environments([first_cvve, second_cvve])
      assert_includes facets, content_facet

      facets = Host::ContentFacet.in_content_view_version_environments([first_cvve])
      assert_includes facets, content_facet
    end
  end

  class ContentFacetErrataTest < ContentFacetBase
    let(:host) { hosts(:one) }

    def test_applicable_errata
      refute_empty content_facet.applicable_errata
    end

    def test_errata_searchable
      other_host = FactoryGirl.create(:host)
      errata = katello_errata(:security)
      found = ::Host.search_for("applicable_errata = #{errata.errata_id}")

      assert_includes found, content_facet.host
      refute_includes found, other_host
    end

    def test_installable_errata_searchable
      other_host = FactoryGirl.create(:host)
      errata = katello_errata(:security)
      found = ::Host.search_for("installable_errata = #{errata.errata_id}")

      refute_includes found, host

      host.content_facet.bound_repositories << errata.repositories.first

      found = ::Host.search_for("installable_errata = #{errata.errata_id}")

      assert_includes found, content_facet.host
      refute_includes found, other_host
    end

    def test_installable_errata_search
      content_facet.bound_repositories = [Katello::Repository.find(katello_repositories(:rhel_6_x86_64_library_view_1).id)]
      content_facet.save!

      host_without_errata = hosts(:without_errata)
      host_without_errata.content_facet.bound_repositories = [Katello::Repository.find(katello_repositories(:rhel_6_x86_64_library_view_1).id)]
      host_without_errata.content_facet.save!

      errata = katello_errata(:security)
      found = ::Host.search_for("installable_errata = #{errata.errata_id}")

      refute_includes found, host_without_errata
      assert_includes found, content_facet.host
    end

    def test_available_and_applicable_errta
      @view_repo = Katello::Repository.find(katello_repositories(:rhel_6_x86_64).id)
      content_facet.bound_repositories = [@view_repo]
      content_facet.save!
      assert_equal_arrays content_facet.applicable_errata, content_facet.installable_errata
    end

    def test_installable_errata
      lib_applicable = content_facet.applicable_errata

      @view_repo = Katello::Repository.find(katello_repositories(:rhel_6_x86_64_library_view_1).id)
      content_facet.bound_repositories = [@view_repo]
      content_facet.save!

      assert_equal_arrays lib_applicable, content_facet.applicable_errata
      refute_equal_arrays lib_applicable, content_facet.installable_errata
      assert_includes content_facet.installable_errata, Erratum.find(katello_errata(:security).id)
    end

    def test_with_installable_errata
      content_facet.bound_repositories = [Katello::Repository.find(katello_repositories(:rhel_6_x86_64_library_view_1).id)]
      content_facet.save!

      content_facet_dev = katello_content_facets(:two)
      content_facet_dev.bound_repositories = [Katello::Repository.find(katello_repositories(:fedora_17_x86_64_dev).id)]
      content_facet_dev.save!

      installable = content_facet_dev.applicable_errata & content_facet_dev.installable_errata
      non_installable = content_facet_dev.applicable_errata - content_facet_dev.installable_errata

      refute_empty non_installable
      refute_empty installable
      content_facets = Katello::Host::ContentFacet.with_installable_errata([installable.first])
      assert_includes content_facets, content_facet_dev

      content_facets = Katello::Host::ContentFacet.with_installable_errata([non_installable.first])
      refute content_facets.include?(content_facet_dev)

      content_facets = Katello::Host::ContentFacet.with_installable_errata([installable.first, non_installable.first])
      assert_includes content_facets, content_facet_dev
    end

    def test_with_non_installable_errata
      @view_repo = Katello::Repository.find(katello_repositories(:rhel_6_x86_64_library_view_1).id)
      content_facet.bound_repositories = [@view_repo]
      content_facet.save!

      unavailable = content_facet.applicable_errata - content_facet.installable_errata
      refute_empty unavailable
      content_facets = Katello::Host::ContentFacet.with_non_installable_errata([unavailable.first])
      assert_includes content_facets, content_facet

      content_facets = Katello::Host::ContentFacet.with_non_installable_errata([content_facet.installable_errata.first])
      refute content_facets.include?(content_facet)
    end

    def test_available_errata_other_view
      @view_repo = Katello::Repository.find(katello_repositories(:rhel_6_x86_64_library_view_1).id)
      content_facet.bound_repositories = [@view_repo]
      content_facet.save!

      available_in_view = content_facet.installable_errata(@library, @library_view)
      assert_equal 1, available_in_view.length
      assert_includes available_in_view, Erratum.find(katello_errata(:security).id)
    end
  end

  class ContentFacetRpmTest < ContentFacetBase
    let(:host_one) { hosts(:one) }
    let(:host_two) { hosts(:two) }
    let(:repo) { katello_repositories(:fedora_17_x86_64) }
    let(:rpm_one) { katello_rpms(:one) }
    let(:rpm_two) { katello_rpms(:two) }
    let(:rpm_three) { katello_rpms(:three) }

    def test_applicable_rpms_searchable
      assert_includes ::Host.search_for("applicable_rpms = #{rpm_one.nvra}"), host_one
      refute_includes ::Host.search_for("applicable_rpms = #{rpm_one.nvra}"), host_two
      refute_includes ::Host.search_for("applicable_rpms = #{rpm_three.nvra}"), host_one
    end

    def test_upgradable_rpms_searchable
      assert_includes rpm_one.repositories, repo
      rpm_two.repositories = []
      host_one.content_facet.bound_repositories << repo

      assert_includes ::Host.search_for("upgradable_rpms = #{rpm_one.nvra}"), host_one
      refute_includes ::Host.search_for("upgradable_rpms = #{rpm_two.nvra}"), host_one
    end

    def test_installable_rpms
      lib_applicable = host_one.applicable_rpms
      cf_one = host_one.content_facet

      cf_one.bound_repositories = []
      cf_one.save!

      assert_equal_arrays lib_applicable, cf_one.applicable_rpms
      refute_equal_arrays lib_applicable, cf_one.installable_rpms
      refute_includes cf_one.installable_rpms, rpm_one
    end
  end

  class ImportErrataApplicabilityTest < ContentFacetBase
    let(:enhancement_errata) { katello_errata(:enhancement) }

    def test_partial_import
      refute_includes host.content_facet.applicable_errata, enhancement_errata

      ::Katello::Pulp::Consumer.any_instance.stubs(:applicable_errata_ids).returns([enhancement_errata.uuid])
      content_facet.import_errata_applicability(true)

      assert_equal [enhancement_errata], content_facet.reload.applicable_errata
    end

    def test_partial_import_empty
      content_facet.applicable_errata << enhancement_errata

      ::Katello::Pulp::Consumer.any_instance.stubs(:applicable_errata_ids).returns([])
      content_facet.import_errata_applicability(true)

      assert_empty content_facet.reload.applicable_errata
    end

    def test_full_import
      ::Katello::Pulp::Consumer.any_instance.stubs(:applicable_errata_ids).returns([enhancement_errata.uuid])
      content_facet.import_errata_applicability(false)

      assert_equal [enhancement_errata], content_facet.reload.applicable_errata
    end
  end

  class ImportRpmApplicabilityTest < ContentFacetBase
    let(:rpm) { katello_rpms(:three) }

    def test_partial_import
      refute_includes host.content_facet.applicable_rpms, rpm

      ::Katello::Pulp::Consumer.any_instance.stubs(:applicable_rpm_ids).returns([rpm.uuid])
      content_facet.import_rpm_applicability(true)

      assert_equal [rpm], content_facet.reload.applicable_rpms
    end

    def test_partial_import_empty
      content_facet.applicable_rpms << rpm

      ::Katello::Pulp::Consumer.any_instance.stubs(:applicable_rpm_ids).returns([])
      content_facet.import_rpm_applicability(true)

      assert_empty content_facet.reload.applicable_rpms
    end

    def test_full_import
      ::Katello::Pulp::Consumer.any_instance.stubs(:applicable_rpm_ids).returns([rpm.uuid])
      content_facet.import_rpm_applicability(false)

      assert_equal [rpm], content_facet.reload.applicable_rpms
    end
  end

  class BoundReposTest < ContentFacetBase
    let(:repo) { katello_repositories(:fedora_17_x86_64) }
    let(:view_repo) { katello_repositories(:fedora_17_x86_64_library_view_1) }

    def test_save_bound_repos_by_path_empty
      ForemanTasks.expects(:async_task).with(Actions::Katello::Host::GenerateApplicability, [host])
      content_facet.expects(:propagate_yum_repos)
      content_facet.bound_repositories << repo

      content_facet.update_repositories_by_paths([])

      assert_empty content_facet.bound_repositories
    end

    def test_save_bound_repos_by_paths
      content_facet.content_view = repo.content_view
      content_facet.lifecycle_environment = repo.environment
      ForemanTasks.expects(:async_task).with(Actions::Katello::Host::GenerateApplicability, [host])
      content_facet.expects(:propagate_yum_repos)
      assert_empty content_facet.bound_repositories

      content_facet.update_repositories_by_paths(["/pulp/repos/#{repo.relative_path}"])

      assert_equal content_facet.bound_repositories, [repo]
    end

    def test_save_bound_repos_by_paths_same_path
      content_facet.content_view = repo.content_view
      content_facet.lifecycle_environment = repo.environment
      content_facet.bound_repositories = [repo]
      ForemanTasks.expects(:async_task).never
      content_facet.expects(:propagate_yum_repos).never

      content_facet.update_repositories_by_paths(["/pulp/repos/#{repo.relative_path}"])

      assert_equal content_facet.bound_repositories, [repo]
    end

    def test_propagate_yum_repos
      content_facet.bound_repositories << repo
      ::Katello::Pulp::Consumer.any_instance.expects(:bind_yum_repositories).with([repo.pulp_id])
      content_facet.propagate_yum_repos
    end

    def test_propagate_yum_repos_non_library
      content_facet.bound_repositories << view_repo
      ::Katello::Pulp::Consumer.any_instance.expects(:bind_yum_repositories).with([view_repo.library_instance.pulp_id])
      content_facet.propagate_yum_repos
    end
  end

  class ContentHostExtensions < ContentFacetBase
    def setup
      assert host #force lazy load
    end

    def test_content_view_search
      assert_includes ::Host::Managed.search_for("content_view = \"#{view.name}\""), host
    end

    def test_content_view_id_search
      assert_includes ::Host::Managed.search_for("content_view_id = #{view.id}"), host
    end

    def test_lifecycle_environment_search
      assert_includes ::Host::Managed.search_for("lifecycle_environment = #{library.name}"), host
    end

    def test_lifecycle_environment_id_search
      assert_includes ::Host::Managed.search_for("lifecycle_environment_id = #{library.id}"), host
    end

    def test_errata_status_search
      status = host.get_status(Katello::ErrataStatus)
      status.status = Katello::ErrataStatus::NEEDED_ERRATA
      status.reported_at = DateTime.now
      status.save!

      assert_includes ::Host::Managed.search_for("errata_status = errata_needed"), content_facet.host
    end

    def test_trace_status_search
      status = host.get_status(Katello::TraceStatus)
      status.status = Katello::TraceStatus::REQUIRE_PROCESS_RESTART
      status.reported_at = DateTime.now
      status.save!

      assert_includes ::Host::Managed.search_for("trace_status = process_restart_needed"), content_facet.host
    end
  end
end
