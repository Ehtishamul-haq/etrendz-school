class BatchTransfersController < ApplicationController
  before_filter :login_required
  filter_access_to :all

  def index
    @batches = Batch.active
  end

  def show_batch
    @batch = Batch.where(:id => params[:id]).includes(:students).order("students.first_name ASC")
    @batches = Batch.active - @batch.to_a
    @batch = @batch.first
  end

  def transfer
      @batch = Batch.where(:id => params[:id]).includes(:students).order("students.first_name ASC").first
      if params[:transfer][:to].present?
        unless params[:transfer][:students].nil?
          students = Student.find(params[:transfer][:students])
          students.each do |s|
            s.batch_students.create(:batch_id => s.batch.id)
            s.update_attribute(:batch_id, params[:transfer][:to])
            s.update_attribute(:has_paid_fees,0)
          end
        end
        batch = @batch
        @stu = Student.where(:batch_id => batch.id)
        if @stu.empty?
          batch.update_attribute :is_active, false
          Subject.where(:batch_id => batch.id).each do |sub|
            sub.employees_subjects.each do |emp_sub|
              emp_sub.delete
            end
          end
        end
        flash[:notice] = "#{t('batch_transfers.flash1')}"
        redirect_to :controller => 'batch_transfers'
      else
        @batches = Batch.active - @batch.to_a
        @batch.errors.add(:base, t('select_a_batch_to_continue'))
        render :template=> "batch_transfers/show_batch"
      end
  end

  def graduation
    @batch = Batch.where(:id => params[:id]).includes(:students).first
    unless params[:ids].nil?
      @ids = params[:ids]
      @id_lists = @ids.map { |st_id| ArchivedStudent.find_by_admission_no(st_id) }
    end
    if request.post?
      student_id_list = params[:graduate][:students]
      @student_list = student_id_list.map { |st_id| Student.find(st_id) } unless student_id_list.nil?
      @admission_list = []
      unless @student_list.blank?
        @student_list.each do |s|
          @admission_list.push s.admission_no
        end
        @student_list.each { |s| s.archive_student(params[:graduate][:status_description]) }
      end
      @stu = Student.where(:batch_id => @batch.id)
      if @stu.empty?
        @batch.update_attribute :is_active, false
        @batch.employees_subjects.destroy_all
        #          flash[:notice]="Graduated selected students successfully."
        #          redirect_to :controller=>'batch_transfers' and return
      end
      flash[:notice]= "#{t('batch_transfers.flash2')}"
      redirect_to :action=>"graduation", :id=>params[:id], :ids => @admission_list
    end
  end

  def subject_transfer
    @batch = Batch.find(params[:id])
    @elective_groups = @batch.elective_groups.all(:conditions => {:is_deleted => false})
    @normal_subjects = @batch.normal_batch_subject
    @elective_subjects = Subject.find_all_by_batch_id(@batch.id,:conditions=>["elective_group_id IS NOT NULL AND is_deleted = false"])
  end

  def get_previous_batch_subjects
    @batch = Batch.find(params[:id])
    course_id = @batch.course_id
    @previous_batch = Batch.find(:first,:order=>'id desc', :conditions=>"batches.id < '#{@batch.id }' AND batches.is_deleted = 0 AND course_id = ' #{course_id }'",:joins=>"INNER JOIN subjects ON subjects.batch_id = batches.id  AND subjects.is_deleted = 0")
    unless @previous_batch.blank?
      @previous_batch_normal_subject = @previous_batch.normal_batch_subject
      @elective_groups = @previous_batch.elective_groups.all(:conditions => {:is_deleted => false})
      @previous_batch_electives = Subject.find_all_by_batch_id(@previous_batch.id,:conditions=>["elective_group_id IS NOT NULL AND is_deleted = false"])
      render(:update) do |page|
        page.replace_html 'previous-batch-subjects', :partial=>"previous_batch_subjects"
      end
    else
      render(:update) do |page|
        page.replace_html 'msg', :text=>"<p class='flash-msg'>#{t('batch_transfers.flash4')}</p>"
      end
    end
  end

  def update_batch
    @batches = Batch.where("course_id = ? and is_deleted = ? and is_active = ? ", params[:course_name], false,  true )
  end

  def assign_previous_batch_subject
    subject = Subject.find(params[:id])
    batch = Batch.find(params[:id2])
    sub_exists = Subject.find_by_batch_id_and_name(batch.id,subject.name, :conditions => { :is_deleted => false})
    if sub_exists.nil?
      if subject.elective_group_id == nil
        Subject.create(:name=>subject.name,:code=>subject.code,:batch_id=>batch.id,:no_exams=>subject.no_exams,
          :max_weekly_classes=>subject.max_weekly_classes,:credit_hours=>subject.credit_hours,:elective_group_id=>subject.elective_group_id,:is_deleted=>false)
      else
        elect_group_exists = ElectiveGroup.find_by_name_and_batch_id(ElectiveGroup.find(subject.elective_group_id).name,batch.id)
        if elect_group_exists.nil?
          elect_group = ElectiveGroup.create(:name=>ElectiveGroup.find(subject.elective_group_id).name,
            :batch_id=>batch.id,:is_deleted=>false)
          Subject.create(:name=>subject.name,:code=>subject.code,:batch_id=>batch.id,:no_exams=>subject.no_exams,
            :max_weekly_classes=>subject.max_weekly_classes,:credit_hours=>subject.credit_hours,:elective_group_id=>elect_group.id,:is_deleted=>false)
        else
          Subject.create(:name=>subject.name,:code=>subject.code,:batch_id=>batch.id,:no_exams=>subject.no_exams,
            :max_weekly_classes=>subject.max_weekly_classes,:credit_hours=>subject.credit_hours,:elective_group_id=>elect_group_exists.id,:is_deleted=>false)
        end
      end
      render(:update) do |page|
        page.replace_html "prev-subject-name-#{subject.id}", :text=>""
        page.replace_html "errors", :text=>"#{subject.name}  #{t('has_been_added_to_batch')}:#{batch.name}"
      end
    else
      render(:update) do |page|
        page.replace_html "prev-subject-name-#{subject.id}", :text=>""
        page.replace_html "errors", :text=>"<div class=\"errorExplanation\" ><p>#{batch.name} #{t('already_has_subject')} #{subject.name}</p></div>"
      end
    end
  end

  def assign_all_previous_batch_subjects
    msg = ""
    err = ""
    batch = Batch.find(params[:id])
    course = batch.course
    all_batches = course.batches(:order=>'id asc')
    all_batches.reject! {|b| b.is_deleted?}
    all_batches.reject! {|b| b.subjects.empty?}
    @previous_batch = all_batches[all_batches.size-2]
    subjects = Subject.find_all_by_batch_id(@previous_batch.id,:conditions=>'is_deleted=false')
    subjects.each do |subject|
      sub_exists = Subject.find_by_batch_id_and_name(batch.id,subject.name, :conditions => { :is_deleted => false})
      if sub_exists.nil?
        if subject.elective_group_id.nil?
          Subject.create(:name=>subject.name,:code=>subject.code,:batch_id=>batch.id,:no_exams=>subject.no_exams,
            :max_weekly_classes=>subject.max_weekly_classes,:credit_hours=>subject.credit_hours,:elective_group_id=>subject.elective_group_id,:is_deleted=>false)
        else
          elect_group_exists = ElectiveGroup.find_by_name_and_batch_id(ElectiveGroup.find(subject.elective_group_id).name,batch.id)
          if elect_group_exists.nil?
            elect_group = ElectiveGroup.create(:name=>ElectiveGroup.find(subject.elective_group_id).name,
              :batch_id=>batch.id,:is_deleted=>false)
            Subject.create(:name=>subject.name,:code=>subject.code,:batch_id=>batch.id,:no_exams=>subject.no_exams,
              :max_weekly_classes=>subject.max_weekly_classes,:credit_hours=>subject.credit_hours,:elective_group_id=>elect_group.id,:is_deleted=>false)
          else
            Subject.create(:name=>subject.name,:code=>subject.code,:batch_id=>batch.id,:no_exams=>subject.no_exams,
              :max_weekly_classes=>subject.max_weekly_classes,:credit_hours=>subject.credit_hours,:elective_group_id=>elect_group_exists.id,:is_deleted=>false)
          end
        end
        msg += "<li> #{t('the_subject')} #{subject.name}  #{t('has_been_added_to_batch')} #{batch.name}</li>"
      else
        err +=   "<li>#{t('batch')} #{batch.name} #{t('already_has_subject')} #{subject.name}" + "</li>"
      end
    end
    @batch = batch
    course = batch.course
    all_batches = course.batches
    @previous_batch = all_batches[all_batches.size-2]
    @previous_batch_normal_subject = @previous_batch.normal_batch_subject
    @elective_groups = @previous_batch.elective_groups
    @previous_batch_electives = Subject.find_all_by_batch_id(@previous_batch.id,:conditions=>["elective_group_id IS NOT NULL AND is_deleted = false"])
    render(:update) do |page|
      page.replace_html 'previous-batch-subjects', :text=>"<p>#{t('subjects_assigned')}</p> "
      unless msg.empty?
        page.replace_html "msg", :text=>"<div class=\"flash-msg\"><ul>" +msg +"</ul></p>"
      end
      unless err.empty?
        page.replace_html "errors", :text=>"<div class=\"errorExplanation\" ><p>#{t('following_errors_found')} :</p><ul>" +err + "</ul></div>"
      end
    end

  end



  def new_subject
    @subject = Subject.new
    @batch = Batch.find params[:id] if request.xhr? and params[:id]
    @elective_group = ElectiveGroup.find params[:id2] unless params[:id2].nil?
    respond_to do |format|
      format.js { render :action => 'new_subject' }
    end
  end

  def create_subject
    @subject = Subject.new(params[:subject])
    @batch = @subject.batch
    if @subject.save
      @subjects = @subject.batch.normal_batch_subject
      @normal_subjects = @subjects
      @elective_groups = ElectiveGroup.find_all_by_batch_id(@batch.id)
      @elective_subjects = Subject.find_all_by_batch_id(@batch.id,:conditions=>["elective_group_id IS NOT NULL AND is_deleted = false"])
    else
      @error = true
    end
  end

end