import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action, computed } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import { cook } from "discourse/lib/text";
import Category from "discourse/models/category";
import dCategoryBadge from "discourse/ui-kit/helpers/d-category-badge";
import dDiscourseTag from "discourse/ui-kit/helpers/d-discourse-tag";
import { featuredTopicsRequest } from "../lib/featured-topics-filter"; // 恢复使用原作者的请求封装
import TlpFeaturedTopic from "./tlp-featured-topic";
import TlpFeaturedTopicsCarousel from "./tlp-featured-topics-carousel";

export default class TlpFeaturedTopicsComponent extends Component {
  @service appEvents;
  @service currentUser;
  @service store;
  @service session;

  @tracked featuredTitle = "";
  @tracked featuredTopics = [];

  featuredTopicsLoadId = 0;

  constructor() {
    super(...arguments);
    this.appEvents.trigger("topic:refresh-timeline-position");

    if (this.showFeaturedTitle) {
      const raw = settings.topic_list_featured_title;
      cook(raw).then((cooked) => (this.featuredTitle = cooked));
    }
  }

  @action
  async getFeaturedTopics() {
    console.log("=== [Debug] getFeaturedTopics 开始执行 ===");

    // 1. 检查开关与 source 配置
    const source = (settings.topic_list_featured_images_tag || "").trim();
    console.log("=== [Debug] featuredImagesEnabled:", this.featuredImagesEnabled, "source:", source);

    if (!this.featuredImagesEnabled || source.length === 0) {
      console.warn("=== [Debug] 开关未开启或标签为空，退出加载 ===");
      this.featuredTopics = [];
      return;
    }

    const loadId = ++this.featuredTopicsLoadId;

    try {
      // 2. 使用原作者封装的请求方法代替死循环，安全且兼容 Discourse API
        const result = await featuredTopicsRequest({
        filterType: settings.topic_list_featured_images_filter_type,
        tag: source,
        categoryId: this.args.category?.id,
        categoryOnly: settings.topic_list_featured_images_from_current_category_only,
      });

      console.log("=== [Debug] 原始请求返回的结构:", result);

      if (loadId !== this.featuredTopicsLoadId) {
        return;
      }

      // 兼容各种返回结构，强制转换为数组
      let allTopics = [];
      if (Array.isArray(result)) {
        allTopics = result;
      } else if (Array.isArray(result?.topics)) {
        allTopics = result.topics;
      } else if (Array.isArray(result?.topic_list?.topics)) {
        allTopics = result.topic_list.topics;
      } else if (result && typeof result === "object") {
        // 如果它返回的是类似 store 查出来的结果
        allTopics = result.topic_list?.topics || result.content || [];
      }

      // 3. 可用图片过滤：剔除没有缩略图的帖子
      let finalTopics = allTopics.filter((topic) => this.hasUsableImage(topic));

      // 4. 分类过滤逻辑
      if (
        this.args.category &&
        settings.topic_list_featured_images_from_current_category_only
      ) {
        finalTopics = finalTopics.filter(
          (topic) => topic.category_id === this.args.category.id
        );
      }

      // 5. 排序 / 随机逻辑
      if (settings.topic_list_featured_images_order === "random") {
        finalTopics = this.shuffle(finalTopics);
      } else if (settings.topic_list_featured_images_order === "created") {
        finalTopics.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
      }

      // 6. 截取最终数量
      const count = Math.max(
        0,
        Number(settings.topic_list_featured_images_count) || 0
      );
      if (count > 0) {
        finalTopics = finalTopics.slice(0, count);
      }

      console.log("=== [Debug] 最终渲染的 featuredTopics 数量:", finalTopics.length);
      this.featuredTopics = finalTopics;

    } catch (error) {
      console.error("=== [Debug] 获取精选主题出错:", error);
    }
  }

  get featuredImagesEnabled() {
    return this.args.category
      ? settings.topic_list_featured_images_category
      : settings.topic_list_featured_images;
  }

  hasUsableImage(topic) {
    return (
      topic.thumbnails?.length > 0 ||
      (settings.topic_list_default_thumbnail_fallback &&
        settings.topic_list_default_thumbnail)
    );
  }

  shuffle(topics) {
    const shuffled = [...topics];
    for (let index = shuffled.length - 1; index > 0; index--) {
      const swapIndex = Math.floor(Math.random() * (index + 1));
      [shuffled[index], shuffled[swapIndex]] = [
        shuffled[swapIndex],
        shuffled[index],
      ];
    }
    return shuffled;
  }

  @computed("featuredTopics")
  get showFeatured() {
    return (
      ((settings.topic_list_featured_images && this.args.category == null) ||
        (settings.topic_list_featured_images_category &&
          this.args.category !== null)) &&
      this.featuredTopics.length > 0
    );
  }

  @computed
  get showFeaturedTitle() {
    return settings.topic_list_featured_title;
  }

  @computed
  get featuredTags() {
    if (settings.topic_list_featured_images_filter_type === "category") {
      return [];
    }
    return (settings.topic_list_featured_images_tag || "").split("|");
  }

  @computed
  get featuredCategory() {
    if (settings.topic_list_featured_images_filter_type !== "category") {
      return;
    }
    return Category.findSingleBySlug(settings.topic_list_featured_images_tag);
  }

  @computed
  get showFeaturedSource() {
    return (
      settings.topic_list_featured_images_source_show &&
      (this.featuredTags.length > 0 || this.featuredCategory)
    );
  }

  get carouselView() {
    return settings.topic_list_featured_images_view_type === "Carousel";
  }

  <template>
    <div
      {{didInsert this.getFeaturedTopics}}
      {{didUpdate this.getFeaturedTopics @category.id}}
      class="tlp-featured-topics
        {{if this.showFeatured 'has-topics'}}
        {{if this.carouselView '--carousel'}}"
    >
      {{#if this.showFeatured}}
        {{#if this.showFeaturedTitle}}
          <div class="featured-title">
            {{this.featuredTitle}}
          </div>
        {{/if}}
        {{#if this.carouselView}}
          <TlpFeaturedTopicsCarousel @topics={{this.featuredTopics}}>
            <:default as |topic|>
              <TlpFeaturedTopic @topic={{topic}} />
            </:default>

            <:positionTrailing>
              {{#if this.showFeaturedSource}}
                <div class="featured-source">
                  {{#if this.featuredCategory}}
                    {{dCategoryBadge this.featuredCategory link=true}}
                  {{else}}
                    {{#each this.featuredTags as |tag|}}
                      {{dDiscourseTag tag}}
                    {{/each}}
                  {{/if}}
                </div>
              {{/if}}
            </:positionTrailing>
          </TlpFeaturedTopicsCarousel>
        {{else}}
          <div class="topics">
            {{#each this.featuredTopics as |t|}}
              <TlpFeaturedTopic @topic={{t}} />
            {{/each}}
          </div>
        {{/if}}
        {{#unless this.carouselView}}
          {{#if this.showFeaturedSource}}
            <div class="featured-source">
              {{#if this.featuredCategory}}
                {{dCategoryBadge this.featuredCategory link=true}}
              {{else}}
                {{#each this.featuredTags as |tag|}}
                  {{dDiscourseTag tag}}
                {{/each}}
              {{/if}}
            </div>
          {{/if}}
        {{/unless}}
      {{/if}}
    </div>
  </template>
}
